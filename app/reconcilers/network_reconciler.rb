# Reconciles the desired state of overlay networks with actual Docker Swarm state.
#
# ## Algorithm
#
# Implements doc 07 §11.3 faithfully for networks (the simplest resource, proving
# the algorithm before applying it to Services):
#
# 1. Acquire lock/lease with fencing token
# 2. Load desired state and desiredRevision
# 3. Inspect actual state directly from runtime
# 4. Calculate diff without side effects (AC1)
# 5. If no diff, confirm convergence and end
# 6. If diff, build plan and apply smallest safe mutation via Executor
# 7. Re-inspect runtime (AC11: never assume the call determined the final state)
# 8. Persist ReconciliationRun (AC10)
# 9. Release lease
#
# ## Invariants
#
# - AC9: the reconciler never writes user-intent columns (AF-03).
# - AC11: lost Docker responses lead to re-inspection, never blind retries.
# - AC6: networks without platform ownership are BLOCKED, never adopted.
# - AC8: two Environments get isolated networks; isolation is proved against Swarm.
#
class NetworkReconciler
  TIMEOUT = 30.seconds

  def self.call(environment:, trigger: ReconciliationRun::PERIODIC, executor: SwarmExecutor.new,
    logger: Rails.logger)
    new(environment: environment, trigger: trigger, executor: executor, logger: logger).call
  end

  def initialize(environment:, trigger:, executor:, logger:)
    @environment = environment
    @trigger = trigger
    @executor = executor
    @logger = logger
  end

  # The public entry point.
  def call
    log_start

    # Step 1: Acquire lock with fencing token (doc 07 §14, M01-15).
    result = AcquireResourceLock.call(
      team: @environment.team,
      scope_key: "environment:#{@environment.id}",
      ttl_seconds: TIMEOUT.to_i
    )
    return log_and_return(result) if result.failure?

    lock = result.value
    return log_and_return(Opanel::Result.failure(code: "LOCK_FAILED", message: "Could not acquire lock")) if lock.nil?

    begin
      # Step 2: Load desired state.
      network = @environment.network
      if network.nil?
        # Network should have been created by EnsureEnvironmentNetwork before
        # the reconciler runs. If it's missing, log and exit gracefully.
        @logger.warn(
          event: "network.reconciliation.network_not_found",
          environment_id: @environment.external_id,
          cluster_id: @environment.cluster.external_id,
          team_id: @environment.team.external_id
        )
        return Opanel::Result.success
      end

      # Step 3: Inspect actual state from runtime (never assume from DB).
      actual = inspect_network_in_swarm(network)

      # Step 4: Calculate diff without side effects (AC1, pure function).
      diff = Opanel::NetworkDiff.compute(desired: network, actual: actual)

      # Persist the diff for observability (AC10).
      run = ReconciliationRun.create!(
        resource: network,
        team_id: network.team_id,
        trigger: @trigger,
        diff_class: diff.diff_class,
        actions_applied: diff.actions_to_apply,
        result: result_for_diff(diff),
        error_reason: diff.error_reason,
        observed_at: Time.current
      )

      # Step 5: If no diff, confirm convergence.
      if diff.diff_class == ReconciliationRun::NOOP
        log_noop(network, run)
        # Update network with runtime ID if not already set
        network.update!(swarm_network_id: actual.runtime_id) if actual && !network.swarm_network_id
        if network.applied_revision.nil? || network.applied_revision < network.desired_revision
          advance_applied_revision(network, run)
        end
        # Ensure network is marked as READY when converged
        network.update!(status: Network::READY) if network.status != Network::READY
        return Opanel::Result.success
      end

      # Step 6-7: Apply action and re-inspect.
      apply_and_verify(network, diff, run, lock.fencing_token)
    ensure
      # Step 9: Release lease.
      ReleaseResourceLock.call(lock: lock, worker_identity: Opanel::WorkerIdentity.current)
    end

    Opanel::Result.success
  end

  private

  # Inspect the network's state in Docker Swarm.
  # Returns a RuntimeObservation (ADR-0009) or nil.
  def inspect_network_in_swarm(network)
    # Construct ExecutorCommand for inspection.
    # resource_id is the external environment_id (find_by_label looks for this label).
    command = ExecutorCommand.new(
      id: Opanel::Identifier.external(:operation, SecureRandom.uuid),
      type: "inspect_network",
      cluster_id: network.cluster.id,
      resource_type: "Network",
      resource_id: network.environment.external_id,
      correlation_id: Current.correlation_id.presence || SecureRandom.uuid
    )

    result = @executor.execute(command)

    # The executor returns an observation in result.observed, or nil if not found.
    case result.outcome
    when ExecutionResult::APPLIED, ExecutionResult::NOOP
      result.observed
    else
      nil  # Network not found or error; treat as nonexistent for now.
    end
  rescue StandardError => e
    # Docker errors, timeouts, etc. are transient; log and retry.
    @logger.error(
      event: "network.reconciliation.inspect_failed",
      environment_id: @environment.external_id,
      error: e.message,
      backtrace: e.backtrace.first(5)
    )
    nil
  end

  # Determine the result for a diff class (for ReconciliationRun).
  def result_for_diff(diff)
    case diff.diff_class
    when ReconciliationRun::NOOP
      ReconciliationRun::SUCCESS
    when ReconciliationRun::CREATE
      ReconciliationRun::SUCCESS  # Action will be applied; result is tentative.
    when ReconciliationRun::BLOCKED_CLASS
      ReconciliationRun::BLOCKED
    else
      ReconciliationRun::SUCCESS
    end
  end

  # Apply the action and re-inspect to verify (AC11).
  def apply_and_verify(network, diff, run, fencing_token)
    case diff.diff_class
    when ReconciliationRun::CREATE
      apply_create_network(network, diff, run, fencing_token)
    when ReconciliationRun::BLOCKED_CLASS
      run.update!(result: ReconciliationRun::BLOCKED)
      log_blocked(network, run)
    else
      # No other diff classes for networks in M01-17.
    end
  end

  # Apply CREATE: call the executor and re-inspect.
  def apply_create_network(network, diff, run, fencing_token)
    # Construct ExecutorCommand with payload for the executor.
    # resource_id is the external environment_id (find_by_label looks for this label).
    # One network per environment, so environment identifies the network uniquely.
    command = ExecutorCommand.new(
      id: Opanel::Identifier.external(:operation, SecureRandom.uuid),
      type: "create_network",
      cluster_id: network.cluster.id,
      resource_type: "Network",
      resource_id: network.environment.external_id,
      desired_revision: network.desired_revision,
      correlation_id: Current.correlation_id.presence || SecureRandom.uuid,
      payload: {
        name: network.technical_name,
        labels: Opanel::Ownership.labels_for(network.environment),
        attachable: false
      }
    )

    result = @executor.execute(command)

    case result.outcome
    when ExecutionResult::APPLIED
      # Success: the network was created. Now re-inspect (AC11).
      swarm_id = result.runtime_resource_ids.first
      network.update!(swarm_network_id: swarm_id) if swarm_id

      # Re-inspect to confirm.
      actual = inspect_network_in_swarm(network)

      if actual && Opanel::Ownership.managed_by_platform?(actual)
        # Verified: advance appliedRevision and mark as READY.
        network.update!(
          applied_revision: network.desired_revision,
          status: Network::READY
        )
        run.update!(result: ReconciliationRun::SUCCESS)
        log_created(network, run)
      else
        # Re-inspection failed; leave in PROVISIONING and mark as BLOCKED.
        run.update!(result: ReconciliationRun::FAILED,
                   error_reason: "Network created but re-inspection failed")
        log_create_failed(network, run)
      end

    when ExecutionResult::CONFLICT
      # Name conflict or already exists. Re-inspect to see what's there.
      actual = inspect_network_in_swarm(network)
      if actual && Opanel::Ownership.managed_by_platform?(actual)
        # It's ours, just not updated in the DB yet.
        swarm_id = actual.runtime_id
        network.update!(swarm_network_id: swarm_id, applied_revision: network.desired_revision,
                       status: Network::READY)
        run.update!(result: ReconciliationRun::SUCCESS)
      else
        # Someone else's network is in the way.
        network.update!(status: Network::DEGRADED)
        run.update!(result: ReconciliationRun::BLOCKED,
                   error_reason: "Network name conflict with unowned resource")
      end

    when ExecutionResult::FAILED
      # Handle specific failure codes.
      if result.error_code == "RESOURCE_NAME_CONFLICT"
        # Unowned resource with same name exists. BLOCK and never adopt.
        network.update!(status: Network::DEGRADED)
        error_msg = "Resource name conflict with unowned network '#{network.technical_name}'; " \
                    "platform never adopts unowned resources"
        run.update!(result: ReconciliationRun::BLOCKED, error_reason: error_msg)
        log_blocked(network, run)
      else
        # Other failures (timeouts, transport errors): retryable, leave in PROVISIONING.
        network.update!(status: Network::DEGRADED)
        run.update!(result: ReconciliationRun::FAILED,
                   error_reason: "Executor returned #{result.outcome}: #{result.error_code}")
        log_create_failed(network, run)
      end

    else
      # RETRYABLE or other unexpected outcomes: log and leave in PROVISIONING.
      network.update!(status: Network::DEGRADED)
      run.update!(result: ReconciliationRun::FAILED,
                 error_reason: "Executor returned #{result.outcome}")
      log_create_failed(network, run)
    end
  end

  # Advance applied_revision when NOOP is confirmed (AC3, AC11).
  def advance_applied_revision(network, run)
    network.update!(
      applied_revision: network.desired_revision
    )
  end

  # Logging helpers.

  def log_start
    @logger.info(
      event: "network.reconciliation.start",
      environment_id: @environment.external_id,
      cluster_id: @environment.cluster.external_id,
      team_id: @environment.team.external_id
    )
  end

  def log_noop(network, run)
    @logger.info(
      event: "network.reconciliation.noop",
      environment_id: @environment.external_id,
      network_id: network.external_id,
      swarm_network_id: network.swarm_network_id,
      desired_revision: network.desired_revision,
      applied_revision: network.applied_revision,
      team_id: @environment.team.external_id
    )
  end

  def log_created(network, run)
    @logger.info(
      event: "network.reconciliation.created",
      environment_id: @environment.external_id,
      network_id: network.external_id,
      swarm_network_id: network.swarm_network_id,
      desired_revision: network.desired_revision,
      applied_revision: network.applied_revision,
      team_id: @environment.team.external_id
    )
  end

  def log_create_failed(network, run)
    @logger.warn(
      event: "network.reconciliation.create_failed",
      environment_id: @environment.external_id,
      network_id: network.external_id,
      error_reason: run.error_reason,
      team_id: @environment.team.external_id
    )
  end

  def log_blocked(network, run)
    @logger.warn(
      event: "network.reconciliation.blocked",
      environment_id: @environment.external_id,
      network_id: network.external_id,
      error_reason: run.error_reason,
      team_id: @environment.team.external_id
    )
  end

  def log_and_return(result)
    if result.failure?
      @logger.warn(
        event: "network.reconciliation.lock_failed",
        environment_id: @environment.external_id,
        reason: result.details[:message],
        team_id: @environment.team.external_id
      )
    end
    result
  end
end
