require "shellwords"

# Converges a Service's Desired State toward what Docker Swarm actually holds
# (doc 07 §11.3, M01-18).
#
# ## The algorithm, unchanged from M01-17's network reconciler
#
#   1. acquire the lease, with its fencing token (doc 07 §14)
#   2. read Desired State and pin the revision this pass is converging to
#   3. inspect Actual State from the runtime — never assumed from the database
#   4. compute the diff, with no side effect (`Opanel::ServiceDiff`)
#   5. no diff: confirm convergence and stop
#   6. diff: apply the smallest safe operation, through the Executor
#   7. **re-inspect**, whatever the mutation answered
#   8. persist the observation and the ReconciliationRun
#   9. release the lease
#
# ## What it may not do
#
# It never writes the user's intent (AF-03): not `name`, `slug`, `image_ref`,
# `replicas`, `ports`, `health_check`, `cpu_*`, `memory_*` or `constraints`. It
# writes what it *observed* — `swarm_service_id`, `applied_revision`, `status`,
# `image_digest` is left alone — and nothing else. It decides no authorization:
# that happened in the Command that recorded the intent.
#
# It also never declares the Service `RUNNING`. Derived status from observed
# tasks is M01-19, and a stored "healthy" boolean is what doc 07 §17.1 forbids.
# This reconciler moves a Service to `PROVISIONING` when it starts applying and
# to `DEGRADED` when it is blocked, and leaves the rest to the observation.
#
# ## appliedRevision is a claim about the runtime (AC10)
#
# It advances only after step 7 returns an observation that is ours, whose image,
# replicas and `com.opanel.desired_revision` label all match what was asked for —
# the same three facts `Opanel::ServiceDiff` decides NOOP from, so the
# confirmation is never weaker than the classification. A mutation's own answer
# is not evidence: ADR-0009 §3 says so, and a lost response (AC5) is exactly the
# case where it would be wrong.
class ServiceReconciler
  TIMEOUT = 30.seconds

  # A newer revision may arrive while this pass is running. The pass converges to
  # the newest one instead of applying the stale one (AC8) — bounded, because an
  # operator holding the save button must not hold a lease forever.
  MAX_CONVERGENCE_PASSES = 3

  # What a `ReconciliationRun` says between the moment it is recorded and the
  # moment the pass reaches an outcome. `ReconciliationRun::RESULTS` is
  # `SUCCESS | BLOCKED | FAILED` and the table belongs to M01-17, so the honest
  # value available here is FAILED with a reason that says which failure it is.
  INCOMPLETE_REASON =
    "The reconcile pass was recorded before it was applied and never reported an outcome. A run left " \
    "in this state was abandoned — the worker died, or the process was stopped — and nothing it " \
    "describes was confirmed against the runtime.".freeze

  NOT_CONVERGED_REASON =
    "Desired State moved on every pass of this lease, so the reconcile spent its convergence budget " \
    "without applying a revision. The sweep picks the Service up again.".freeze

  # Desired State becomes an executor payload here, and only here.
  #
  # Units: `cpu_*` are millicores and `memory_*` are MiB. Neither is documented
  # in the schema or in M01-12 — doc 03 §5.1 speaks in CPUs and MiB, and the
  # factory writes 100/200 and 256/512 — so the reading is named in constants
  # rather than inlined. A wrong reading here is a 1000x resource error, which
  # is why it is recorded as an inferred unit in the Story report instead of
  # being buried in an expression.
  module SpecTranslation
    NANOCPUS_PER_MILLICORE = 1_000_000
    BYTES_PER_MIB = 1_048_576
    NANOSECONDS_PER_SECOND = 1_000_000_000

    # Conservative and fixed. Rollout health verification and automatic rollback
    # are M06-04..M06-06; until they exist, a failed update pauses and waits for
    # a human rather than deciding on its own.
    UPDATE_CONFIG = {
      "Parallelism" => 1,
      "Delay" => 5 * NANOSECONDS_PER_SECOND,
      "FailureAction" => "pause",
      "Order" => "stop-first"
    }.freeze

    module_function

    # The digest-pinned reference, or nil when nothing pins it (AC2).
    #
    # Resolving a mutable tag against the registry is SC-21's other half and is
    # not done here: the Engine allowlist has no registry read, and
    # `config/architecture/docker-lab.yml` states that the lab — where this code
    # is proved — is deliberately usable without registry access. An unpinned
    # image is refused by the diff, visibly, rather than deployed by tag.
    def image_for(service)
      parsed = Opanel::ImageRef.new(service.image_ref).parse
      digest = parsed[:digest].presence || service.image_digest.presence
      return nil if digest.blank?

      "#{parsed[:registry]}/#{parsed[:repository]}@#{digest}"
    rescue Opanel::ImageRef::InvalidReference
      nil
    end

    # A Swarm `Spec.Name` and the set of attached networks are fixed at create
    # time: `update_service_spec` does not accept them, and sending them would
    # be refused by the executor's allowlist before the daemon was reached.
    UPDATE_KEYS = %i[image command args env replicas labels resources placement healthcheck
                     update_config].freeze

    def payload_for(service, network:)
      {
        name: service.technical_name,
        image: image_for(service),
        command: argv(service.command),
        args: argv(service.args),
        replicas: service.replicas,
        labels: Opanel::Ownership.labels_for(service),
        networks: [ network.swarm_network_id ],
        resources: resources(service),
        placement: Array(service.constraints).presence,
        healthcheck: healthcheck(service.health_check),
        update_config: UPDATE_CONFIG
      }.compact
    end

    def argv(value)
      return nil if value.blank?

      Shellwords.split(value.to_s)
    rescue ArgumentError
      nil
    end

    def resources(service)
      values = {
        "cpu_reservation_nano" => scale(service.cpu_reservation, NANOCPUS_PER_MILLICORE),
        "cpu_limit_nano" => scale(service.cpu_limit, NANOCPUS_PER_MILLICORE),
        "memory_reservation_bytes" => scale(service.memory_reservation, BYTES_PER_MIB),
        "memory_limit_bytes" => scale(service.memory_limit, BYTES_PER_MIB)
      }.compact

      values.presence
    end

    def scale(value, factor) = value.nil? ? nil : value.to_i * factor

    def healthcheck(declared)
      return nil if declared.blank?

      config = declared.with_indifferent_access
      {
        "Test" => config[:test],
        "Interval" => seconds_to_nanoseconds(config[:interval_seconds]),
        "Timeout" => seconds_to_nanoseconds(config[:timeout_seconds]),
        "StartPeriod" => seconds_to_nanoseconds(config[:start_period_seconds]),
        "Retries" => config[:retries]
      }.compact.presence
    end

    def seconds_to_nanoseconds(value) = value.nil? ? nil : value.to_i * NANOSECONDS_PER_SECOND
  end

  def self.call(service:, trigger: ReconciliationRun::PERIODIC, operation: nil,
    executor: SwarmExecutor.new, logger: Rails.logger)
    new(service: service, trigger: trigger, operation: operation, executor: executor,
      logger: logger).call
  end

  def initialize(service:, trigger:, operation:, executor:, logger:)
    @service = service
    @trigger = trigger
    @operation = operation
    @executor = executor
    @logger = logger
  end

  def call
    log(:start)

    acquisition = AcquireResourceLock.call(
      team: @service.team,
      scope_key: "service:#{@service.id}",
      ttl_seconds: TIMEOUT.to_i
    )
    return lock_failed(acquisition) if acquisition.failure?

    lock = acquisition.value
    return lock_failed(Opanel::Result.failure(code: "LOCK_FAILED", message: "no lease")) if lock.nil?

    begin
      MAX_CONVERGENCE_PASSES.times do
        outcome = reconcile_once(lock)
        return outcome unless outcome == :superseded
      end

      # Every pass was superseded or conflicted and the budget is spent. That is
      # not a success: nothing converged, and the caller that reports it as one
      # is the reason a stuck rollout looks healthy. The Operation reaches a
      # terminal state here rather than being left `RUNNING` for M01-14's
      # stalled sweep to find — `drive_operation` leaves an already-terminal
      # row (a supersession) alone.
      exhausted(lock)
    ensure
      # The identity the lease was taken under, never `anything`: releasing a
      # lease you do not own is how a successor loses one it does (M01-15 AC5).
      ReleaseResourceLock.call(lock: lock, worker_identity: Opanel::WorkerIdentity.current)
    end
  end

  private

  attr_reader :executor

  def reconcile_once(lock)
    @service.reload
    target_revision = @service.desired_revision
    network = @service.environment.network
    desired_image = SpecTranslation.image_for(@service)

    actual = inspect_service
    diff = Opanel::ServiceDiff.compute(service: @service, desired_image: desired_image,
      network: network, actual: actual)

    run = ReconciliationRun.create!(
      resource: @service,
      team_id: @service.team_id,
      trigger: @trigger,
      diff_class: diff.diff_class,
      actions_applied: diff.actions_to_apply,
      # Written before anything is applied, so it says the pass has not
      # finished — never that it succeeded. A worker that dies between this
      # line and `verify` (AC7) leaves the row exactly as it is, and a run that
      # claims SUCCESS for a pass that never converged is the stored-boolean
      # failure mode doc 07 §17.1 forbids, in a different place (review F-2).
      result: ReconciliationRun::FAILED,
      error_reason: diff.error_reason.presence || INCOMPLETE_REASON,
      observed_at: Time.current
    )

    case diff.diff_class
    when ReconciliationRun::NOOP
      converged(actual, run, target_revision, lock)
    when ReconciliationRun::BLOCKED_CLASS
      blocked(run, diff.error_reason, lock)
    else
      # A newer revision may have arrived between the Command that asked for this
      # pass and this line. Applying the older one would overwrite intent with a
      # revision the operator already replaced (AC8).
      return supersede(run, target_revision, lock) if @service.reload.desired_revision != target_revision

      apply(diff, actual, network, run, target_revision, lock)
    end
  end

  # ---- observation ---------------------------------------------------------

  # ADR-0009 §5: a Service is addressed by its ownership label, never by a
  # runtime id the platform guessed.
  def inspect_service
    result = executor.execute(executor_command("inspect_service"))
    result.converged? ? result.observed : nil
  end

  def executor_command(type, **payload)
    ExecutorCommand.new(
      id: Opanel::Identifier.external(:operation, Opanel::Identifier.generate),
      type: type,
      cluster_id: @service.environment.cluster_id,
      resource_type: "Service",
      resource_id: @service.external_id,
      desired_revision: @service.desired_revision,
      correlation_id: Current.correlation_id.presence || SecureRandom.uuid,
      payload: payload
    )
  end

  # ---- applying ------------------------------------------------------------

  def apply(diff, actual, network, run, target_revision, lock)
    payload = SpecTranslation.payload_for(@service, network: network)
    @service.update!(status: Service::PROVISIONING) if @service.draft?
    start_operation(lock)

    result =
      if diff.diff_class == ReconciliationRun::CREATE
        create(payload)
      else
        update(payload, actual)
      end

    # A conflict is not a failure: something moved under us. Re-observe and let
    # the next pass recompute the diff against what is actually there (AC6).
    return recompute_after_conflict(run) if result.conflict?

    unless result.converged?
      return failure(run, lock, "the Engine answered #{result.outcome}" \
                                "#{result.error_code ? " (#{result.error_code})" : ''}")
    end

    verify(run, target_revision, lock)
  end

  def create(payload)
    result = executor.execute(executor_command("create_service", **payload))
    observe_before_repeating(result, "create_service", payload)
  end

  def update(payload, actual)
    # The CAS baseline is the version observed in step 3, never one read at the
    # moment of writing: that is the blind read-modify-write the executor's
    # contract exists to refuse.
    revision = payload.slice(*SpecTranslation::UPDATE_KEYS).merge(version: actual&.version)
    result = executor.execute(executor_command("update_service_spec", **revision))
    observe_before_repeating(result, "update_service_spec", revision)
  end

  # AC5. A lost answer is not a failure and must never be resent blindly: the
  # executor observes Actual State first and only re-issues if the runtime does
  # not already show the effect.
  def observe_before_repeating(result, type, payload)
    return result unless result.observe_before_retry

    log(:unknown_outcome, outcome: result.outcome, error_code: result.error_code)
    executor.retry_after_observing(executor_command(type, **payload))
  end

  # ---- verifying -----------------------------------------------------------

  # Step 7 and 8. `appliedRevision` advances here or not at all (AC10).
  def verify(run, target_revision, lock)
    actual = inspect_service

    unless converged_on?(actual, target_revision)
      return failure(run, lock, "the runtime did not confirm the applied revision on re-inspection")
    end

    blocking = blocking_code
    return blocked(run, blocking_reason(blocking), lock) if blocking

    @service.update!(swarm_service_id: actual.runtime_id, applied_revision: target_revision)
    run.update!(result: ReconciliationRun::SUCCESS, error_reason: nil)
    audit(:service_deployed, "SUCCESS")
    complete_operation(lock, Operation::SUCCEEDED)
    log(:applied, applied_revision: target_revision, swarm_service_id: actual.runtime_id)

    Opanel::Result.success(converged: true)
  end

  # The confirmation has to read the same evidence as the classification it
  # confirms. `Opanel::ServiceDiff` decides NOOP from image, replicas **and**
  # `com.opanel.desired_revision`, because ADR-0009 §2's attribute allowlist
  # cannot see args, env, resources, placement or the healthcheck — the label is
  # the only witness that an invisible change landed. Confirming on image and
  # replicas alone advances `applied_revision` against an observation whose
  # label still names the old revision, and the next pass then classifies
  # ROLLOUT forever (review F-5).
  def converged_on?(actual, target_revision)
    return false if actual.nil?
    return false unless Opanel::Ownership.managed_by_platform?(actual)

    actual.attributes["image"].to_s == SpecTranslation.image_for(@service).to_s &&
      actual.attributes["replicas"].to_i == @service.replicas.to_i &&
      applied_revision_label(actual) == target_revision.to_s
  end

  def applied_revision_label(actual)
    actual.labels["#{Opanel::Ownership::NAMESPACE}.desired_revision"].to_s
  end

  # AC9. The daemon accepts a Service it cannot schedule and a digest it cannot
  # resolve, so the only observable cause is the task. One read, one
  # classification — counting replicas and deriving health is M01-19.
  def blocking_code
    result = executor.execute(executor_command("list_tasks"))
    return nil unless result.converged?

    result.safe_metadata[:blocking_code]
  end

  def blocking_reason(code)
    case code
    when "IMAGE_UNAVAILABLE"
      "The Engine could not resolve the image digest for this Service. The deploy is blocked until the " \
      "image is available; it is not retried aggressively."
    when "PLACEMENT_IMPOSSIBLE"
      "No node satisfies this Service's placement constraints, so its tasks cannot be scheduled. The " \
      "deploy is blocked until a node matches; it is not retried aggressively."
    else
      "The Service's tasks are not running and the Engine reported #{code}."
    end
  end

  # ---- outcomes ------------------------------------------------------------

  def converged(actual, run, target_revision, lock)
    # The spec agrees, which is not the same as the workload running. A Service
    # whose tasks cannot be scheduled or whose digest cannot be resolved is
    # blocked, and stays blocked until something changes — that is AC9, and it
    # is checked on every pass because the daemon accepts the create and only
    # the tasks, seconds later, say otherwise.
    blocking = blocking_code
    return blocked(run, blocking_reason(blocking), lock) if blocking

    if actual && @service.swarm_service_id != actual.runtime_id
      @service.update!(swarm_service_id: actual.runtime_id)
    end

    if @service.applied_revision.nil? || @service.applied_revision < target_revision
      @service.update!(applied_revision: target_revision)
    end

    run.update!(result: ReconciliationRun::SUCCESS, error_reason: nil)
    complete_operation(lock, Operation::SUCCEEDED)
    log(:noop, applied_revision: @service.applied_revision)
    Opanel::Result.success(converged: true)
  end

  def blocked(run, reason, lock)
    run.update!(result: ReconciliationRun::BLOCKED, error_reason: reason)
    @service.update!(status: Service::DEGRADED) if @service.can_transition_to?(Service::DEGRADED)
    audit(:service_reconcile_blocked, "FAILED")
    complete_operation(lock, Operation::FAILED)
    log(:blocked, error_reason: reason)

    Opanel::Result.failure(code: "BLOCKED", message: reason)
  end

  # An Engine rejection and a re-inspection that did not confirm are both the end
  # of this Operation, not a pause in it. `start_operation` already moved the row
  # to `RUNNING`; leaving it there with the lease released makes the Operation
  # depend on M01-14's stalled sweep to ever finish (review F-3).
  def failure(run, lock, reason)
    run.update!(result: ReconciliationRun::FAILED, error_reason: reason)
    @service.update!(status: Service::DEGRADED) if @service.can_transition_to?(Service::DEGRADED)
    complete_operation(lock, Operation::FAILED)
    log(:failed, error_reason: reason)

    Opanel::Result.failure(code: "RECONCILE_FAILED", message: reason)
  end

  def exhausted(lock)
    complete_operation(lock, Operation::FAILED)
    log(:not_converged, error_reason: NOT_CONVERGED_REASON)

    Opanel::Result.failure(code: "NOT_CONVERGED", message: NOT_CONVERGED_REASON)
  end

  def recompute_after_conflict(run)
    run.update!(result: ReconciliationRun::FAILED,
      error_reason: "The runtime revision moved while this pass was applying; the diff is recomputed " \
                    "against a fresh observation.")
    log(:conflict)

    :superseded
  end

  # AC8. The Operation that asked for the older revision is terminal, and the
  # next pass converges to the newest Desired State.
  def supersede(run, target_revision, lock)
    run.update!(result: ReconciliationRun::FAILED,
      error_reason: "Revision #{target_revision} was superseded by #{@service.desired_revision} " \
                    "before it was applied.")
    supersede_operation(lock)
    log(:superseded, superseded_revision: target_revision, target_revision: @service.desired_revision)

    :superseded
  end

  def lock_failed(result)
    # `Opanel::Result` carries the reason in `message`; `details` is the extra
    # bag and is empty here. The network reconciler reads `details[:message]`
    # and logs nil for every lock failure — recorded as inherited debt rather
    # than fixed, because `app/reconcilers/network_reconciler.rb` belongs to
    # M01-17 and to no boundary of this Story.
    log(:lock_failed, error_reason: result.message)
    result
  end

  # ---- the Operation -------------------------------------------------------

  # An Operation is driven through the states doc 07 §5.2 declares, never
  # jumped: a `QUEUED` Operation that finishes passes through `RUNNING` on the
  # way to `SUCCEEDED`, and supersession is reached from `QUEUED` — which is
  # exactly why the job leaves it `QUEUED` until this pass decides to apply.
  def complete_operation(lock, status)
    drive_operation(lock, Operation::RUNNING) unless @operation&.status == Operation::RUNNING
    drive_operation(lock, status, finished_at: Time.current)
  end

  def supersede_operation(lock)
    drive_operation(lock, Operation::SUPERSEDED, finished_at: Time.current)
  end

  def start_operation(lock)
    drive_operation(lock, Operation::RUNNING, started_at: Time.current)
  end

  def drive_operation(lock, status, **attributes)
    return if @operation.nil? || @operation.terminal?
    return unless @operation.can_transition_to?(status)

    if @operation.lease_owner.present?
      @operation.update_with_fencing_token(fencing_token: @operation.fencing_token, lock: lock,
        status: status, **attributes)
    else
      @operation.update!(status: status, **attributes)
    end
  end

  # ---- audit and logs ------------------------------------------------------

  def audit(action, result)
    AuditTrail.record(action: action, actor: AuditTrail::SYSTEM, resource: @service,
      team: @service.team, result: result, operation_id: @operation&.id)
  end

  def log(event, **fields)
    severity = %i[blocked failed not_converged lock_failed unknown_outcome].include?(event) ? :warn : :info

    @logger.public_send(
      severity,
      {
        event: "service.reconciliation.#{event}",
        service_id: @service.external_id,
        environment_id: @service.environment.external_id,
        team_id: @service.team.external_id,
        operation_id: @operation&.external_id,
        desired_revision: @service.desired_revision,
        # doc 07 §23: fast while a rollout is in flight, minutes when stable.
        # The cadence itself is `config/recurring.yml`; this field says when the
        # sweep is expected to look again.
        next_check_at: next_check_at(event)
      }.merge(fields)
    )
  end

  def next_check_at(event)
    return nil if %i[noop applied].include?(event)

    (Time.current + Opanel::Configuration.service_reconcile_cadence_seconds.seconds).iso8601
  end
end
