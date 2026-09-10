# Turns this machine into the first node of a Swarm, and registers it (UC-003, AC1).
#
# ## The order is preflight, then decide, then act
#
# doc 06 §3.3 draws the sequence and doc 06 §3.1 says the installer aborts on
# conditions it cannot verify. So: run every check, refuse if any of them FAILs
# (AC4), and only then touch the Engine. A bootstrap that starts and then
# discovers the clock is wrong has already created a Swarm somebody has to tear
# down.
#
# ## An existing Swarm is adopted, never overwritten (AC6)
#
# If the daemon is already in a Swarm, this **never** runs `swarm init` — that
# would fail anyway, and if it did not it would mean rebuilding a cluster
# somebody is running workloads on. It adopts, and only when adoption is safe:
# the node must be a manager (a worker cannot be a control plane), and the Swarm
# must not already be registered under another Cluster row. Both refusals name
# what is wrong.
#
# ## Nothing here runs inside a transaction
#
# `AGENT_RULES` is explicit that a network call never happens inside a PostgreSQL
# transaction, and `swarm init` is a network call to the daemon that can take
# seconds. The row is written **after** the Engine has answered, in a short
# transaction that also writes the audit record (M01-05 AC11).
#
# ## The join token
#
# It is never read, never returned and never logged (AC10). `SwarmBootstrap.init`
# discards the command output that carries it and reads the Swarm id back from
# the daemon; every message this Command formats goes through `redact` on the way
# out, so a token that reached an error string cannot reach a log.
class BootstrapCluster
  NAME_REQUIRED = "Enter a name for the cluster."
  NAME_TOO_LONG = "That name is too long."
  SLUG_UNUSABLE = "Choose a name that contains at least one letter or number."
  SLUG_INVALID = "A URL name may use lowercase letters, numbers and hyphens only."
  SLUG_TAKEN = "That URL name is already used by another cluster in this team."

  PREFLIGHT_BLOCKED = "The machine is not ready to become a cluster node."
  ADVERTISE_REQUIRED = "This machine has more than one address. Choose the one other nodes will use."
  ADVERTISE_UNKNOWN = "That address is not one of this machine's."
  NOT_A_MANAGER = "This node belongs to a Swarm as a worker, so it cannot host the control plane."
  ALREADY_REGISTERED = "That Swarm is already registered as another cluster."

  def self.call(actor:, team:, name:, slug: nil, advertise_address: nil, adopt_existing: false,
    preflight: nil, executor: SwarmBootstrap)
    new(actor: actor, team: team, name: name, slug: slug, advertise_address: advertise_address,
      adopt_existing: adopt_existing, preflight: preflight, executor: executor).call
  end

  def initialize(actor:, team:, name:, slug:, advertise_address:, adopt_existing:, preflight:, executor:)
    @actor = actor
    @team = team
    @name = name.to_s.strip
    @requested_slug = slug.to_s.strip.downcase.presence
    @advertise_address = advertise_address.to_s.strip.presence
    @adopt_existing = adopt_existing
    @executor = executor
    @preflight = preflight
  end

  def call
    denial = authorization_refusal
    return denial if denial

    error = validate
    return error if error

    report = preflight_report
    return blocked(report) if report.blocked?

    engine = report.engine
    return unreachable(engine) if engine.is_a?(SwarmBootstrap::EngineError)

    engine.swarm_active? ? adopt(engine, report) : initialise(report)
  rescue SwarmBootstrap::EngineError => error
    # The Engine failed *during* the bootstrap. Recorded and reported with the
    # classified cause, never as a generic failure (AC7).
    unreachable(error)
  end

  private

  attr_reader :actor, :team, :name, :requested_slug, :advertise_address, :executor

  def adopt_existing? = @adopt_existing

  def candidate
    @candidate ||= Cluster.new(team: team, name: name.presence || "cluster",
      slug: resolved_slug || "cluster", status: Cluster::PROVISIONING)
  end

  # The decision belongs to `ClusterPolicy#bootstrap?` — the Team role of doc 04
  # §6.2 *and* the instance role of doc 04 §7.1, both resolved there — not to a
  # role list written here.
  #
  # The Policy is named and its predicate called rather than reached through a
  # generic helper, which is the pattern `SuspendTeamMember` established: `grep
  # bootstrap?` is how the next person finds where this permission is decided,
  # and AF-07 reads the Command for exactly this to prove the mutation has an
  # authorization path.
  #
  # It is authorized against an **unsaved** Cluster carrying the target Team.
  # There is no Cluster yet, and `team_id` is NOT NULL (SC-12), so there is always
  # a Team to scope the decision to.
  def authorization_refusal
    policy = ClusterPolicy.new(actor, candidate)
    return nil if policy.bootstrap?

    # Only on the denied path, and only then, is the reason worth a second
    # evaluation: it separates "you are not on this Team" from "you are, but
    # without the role" and from "you do not administer this installation".
    decision = policy.decide(:bootstrap)
    Opanel::Authorization.record(actor, decision)

    # A denial for want of a membership is answered as NOT_FOUND, the same answer
    # a Team that does not exist gets: an actor outside the Team must not learn
    # that it exists (Annex C §7.3).
    if decision.reason == :no_membership
      return Opanel::Result.failure(code: "NOT_FOUND", message: "That team could not be found.",
        details: {})
    end

    # Everything else is a refusal to somebody who may already see the Team. The
    # message does not say which of the two conditions failed — telling an actor
    # whether they lack the role or the instance grant is an oracle about the
    # installation.
    Opanel::Result.failure(code: "FORBIDDEN",
      message: "Your role does not allow initializing a cluster.", details: {})
  end

  def preflight_report
    @preflight_report ||= @preflight || Preflight.call(executor: executor)
  end

  def validate
    return failure("VALIDATION_ERROR", NAME_REQUIRED, field: "name") if name.blank?
    return failure("VALIDATION_ERROR", NAME_TOO_LONG, field: "name") if name.length > Cluster::NAME_MAX_LENGTH

    slug = resolved_slug
    return failure("VALIDATION_ERROR", slug_error, field: "slug") if slug.nil?
    return slug_taken if taken?(slug)

    nil
  end

  # `swarm init` on a machine that already has a Swarm. Adoption is the whole
  # answer here, and it is conditional (AC6).
  def adopt(engine, report)
    return failure("CONFLICT", NOT_A_MANAGER, field: "swarm") unless engine.manager?

    unless adopt_existing?
      return failure("CONFLICT",
        "This machine already belongs to Swarm #{engine.swarm_id}. Adopt it explicitly to register it.",
        field: "swarm", swarm_id: engine.swarm_id, adoptable: true)
    end

    # The partial unique index enforces this too; checking first turns a database
    # error into a sentence the operator can act on.
    if Cluster.kept.where(swarm_id: engine.swarm_id).exists?
      return failure("CONFLICT", ALREADY_REGISTERED, field: "swarm")
    end

    persist(engine: engine, report: report, advertise: engine_advertise_address(report),
      action: :cluster_adopted)
  rescue ActiveRecord::RecordNotUnique
    failure("CONFLICT", ALREADY_REGISTERED, field: "swarm")
  end

  def initialise(report)
    address = chosen_advertise_address(report)
    return address if address.is_a?(Opanel::Result)

    swarm_id = executor.init(advertise_address: address)

    engine = executor.info
    persist(engine: engine, report: report, advertise: address, action: :cluster_bootstrapped)
  rescue ActiveRecord::RecordNotUnique
    failure("CONFLICT", ALREADY_REGISTERED, field: "swarm")
  end

  # AC5: with more than one candidate the operator chooses, and the choice has to
  # be one of this machine's addresses — a typo that is silently accepted becomes
  # a Swarm no other node can reach.
  def chosen_advertise_address(report)
    if advertise_address
      # `interfaces` is `nil` when the machine's list could not be enumerated,
      # which is a different answer from "it has none". Calling `.map` on it raised
      # `NoMethodError` — a refusal turning into a crash, which is the shape the
      # preflight spends a whole file avoiding. Review found it.
      known = (report.interfaces || []).map(&:address)
      return failure("VALIDATION_ERROR", ADVERTISE_UNKNOWN, field: "advertiseAddress",
        candidates: report.advertise_candidates.map(&:address)) unless known.include?(advertise_address)

      return advertise_address
    end

    if report.advertise_address_required?
      return failure("VALIDATION_ERROR", ADVERTISE_REQUIRED, field: "advertiseAddress",
        candidates: report.advertise_candidates.map(&:address))
    end

    report.suggested_advertise_address ||
      failure("VALIDATION_ERROR", ADVERTISE_REQUIRED, field: "advertiseAddress", candidates: [])
  end

  # An adopted Swarm was advertised by whoever created it, and this Command does
  # not know on what. Recording the operator's answer when they gave one is
  # better than recording a guess.
  def engine_advertise_address(report) = advertise_address || report.suggested_advertise_address

  def persist(engine:, report:, advertise:, action:)
    cluster = nil
    observed = Time.current

    ApplicationRecord.transaction do
      cluster = Cluster.create!(
        team: team, name: name, slug: resolved_slug,
        status: derived_status(engine, report), swarm_id: engine.swarm_id,
        advertise_address: advertise, observed_at: observed,
        unreachable_reason: nil, desired_revision: 1
      )

      AuditTrail.record(action: action, actor: actor, resource: cluster,
        after: cluster.attributes)
    end

    Rails.logger.info(event: "cluster.#{action}", team_id: team.external_id,
      cluster_id: cluster.external_id, actor_id: actor.external_id,
      swarm_id: cluster.swarm_id, result: "succeeded")

    Opanel::Result.success(cluster: cluster, preflight: report)
  end

  # AC11 in one place: the status is what was just observed, and `observed_at`
  # says when. A single-node Swarm with a manager that answers is `READY`;
  # anything the preflight could not verify makes it `DEGRADED`, because
  # "operational but unverified" is not the same claim as "operational".
  def derived_status(engine, report)
    return Cluster::DEGRADED unless engine.manager? && engine.swarm_active?
    return Cluster::DEGRADED if report.unknowns.any?

    Cluster::READY
  end

  def resolved_slug
    @resolved_slug ||= requested_slug || Cluster.slugify(name)
  end

  def slug_error = requested_slug ? SLUG_INVALID : SLUG_UNUSABLE

  def taken?(slug)
    return true unless slug.match?(Cluster::SLUG_FORMAT)

    team.clusters.kept.exists?(slug: slug)
  end

  def slug_taken
    failure("VALIDATION_ERROR", SLUG_TAKEN, field: "slug")
  end

  def blocked(report)
    names = report.failures.map(&:name)

    # Audited for the same reason the unreachable path is: an authorized actor
    # attempted a privileged action and it did not produce a cluster. The trail
    # answers "who has been trying this, and what keeps stopping them" — which a
    # trail of successes cannot.
    record_failure(names.join(","))

    failure("PREFLIGHT_FAILED", PREFLIGHT_BLOCKED, field: "preflight",
      failed_checks: report.failures.map { |check| { name: check.name, detail: check.detail } })
  end

  # AC7: a daemon that is absent, refusing or slow arrives as its own cause, and
  # the Cluster is not created — there is nothing to register.
  #
  # It is **audited**, not only logged. An authorized actor tried to turn a
  # machine into a cluster node and the attempt failed: doc 04 §10 wants the
  # privileged action recorded with its result, and a trail that holds only the
  # successes cannot answer "who has been trying this, and against what". The
  # action was declared and never emitted until review pointed out that a
  # declaration nobody writes is the same dead shape as a rule nobody enforces.
  def unreachable(error)
    detail = SwarmBootstrap.redact(error.message)

    Rails.logger.warn(event: "cluster.bootstrap_failed", team_id: team&.external_id,
      actor_id: actor&.external_id, cause: error.cause_code,
      detail: detail, result: "failed")

    record_failure(error.cause_code)

    failure("ENGINE_UNAVAILABLE", detail, field: "docker", cause: error.cause_code)
  end

  # Outside any transaction, and deliberately: nothing was mutated, so there is
  # nothing for a failed insert to roll back — and losing the request because the
  # trail could not be written would turn an audit problem into an outage. Same
  # reasoning as `Opanel::Authorization.record_denial`.
  def record_failure(reason)
    AuditTrail.record(action: :cluster_bootstrap_failed, actor: actor, resource: "Cluster",
      team: team, result: "FAILED",
      # The classified vocabulary only — a cause code, or the names of the checks
      # that failed. The Engine's own message can carry a path or a token, and the
      # allowlist would drop an unknown key anyway; recording the words the UI and
      # the trail already share is what makes it filterable.
      after: { "unreachable_reason" => reason })
  rescue StandardError => audit_error
    # A trail that cannot be written must not hide the failure the operator asked
    # about. Reported, never swallowed silently.
    Rails.logger.error(event: "cluster.bootstrap_failed.audit_failed",
      detail: audit_error.class.name)
  end

  def failure(code, message, **details)
    Rails.logger.info(event: "cluster.bootstrapped", team_id: team&.external_id,
      actor_id: actor&.external_id, result: "rejected", reason: details[:field])

    Opanel::Result.failure(code: code, message: SwarmBootstrap.redact(message), details: details)
  end
end
