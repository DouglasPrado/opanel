# Ensures an Environment has an overlay network, creating Operation if needed (M01-17 AC1).
#
# ## Purpose
#
# Called by CreateEnvironment: after the Environment exists, this command creates a
# Network record and an Operation that triggers the reconciler to create the Swarm
# overlay network. It follows the M01-13 pattern exactly: Desired State + Operation +
# OutboxEvent in one transaction.
#
# ## Idempotency
#
# If the network already exists, this is a no-op. The Environment.network association
# prevents race conditions via a unique constraint (networks unique per environment).
#
class EnsureEnvironmentNetwork
  NETWORK_CREATE_FAILED = "Could not create network record."

  def self.call(actor:, environment:)
    new(actor: actor, environment: environment).call
  end

  def initialize(actor:, environment:)
    @actor = actor
    @environment = environment
  end

  def call
    # Authorization: same as CreateEnvironment's team.
    policy = EnvironmentPolicy.new(@actor, @environment)
    return failure("CONFLICT", ApplicationPolicy::REASONS[:insufficient_role]) unless policy.update?

    # Idempotency: if the network already exists, return success.
    if @environment.network.present?
      Rails.logger.debug(event: "ensure_environment_network.idempotent",
        environment_id: @environment.external_id,
        network_id: @environment.network.external_id)
      return Opanel::Result.success(network: @environment.network)
    end

    persist_network
  rescue ActiveRecord::RecordNotUnique
    # Race: another process created the network. Reload and return.
    @environment.reload
    Opanel::Result.success(network: @environment.network)
  end

  private

  attr_reader :actor, :environment

  def persist_network
    network = nil
    operation = nil

    ApplicationRecord.transaction do
      # Create the Network record (desired state).
      network = Network.create!(
        environment: environment,
        cluster: environment.cluster,
        team: environment.team,
        name: environment.technical_name,
        driver: Network::OVERLAY,
        encrypted: false,
        status: Network::PROVISIONING,
        desired_revision: 1
      )

      # Create the Operation (M01-13 pattern).
      operation = Operation.create!(
        team: environment.team,
        resource_type: "Network",
        resource_id: network.id,
        type: "CREATE_NETWORK",
        status: Operation::PENDING,
        desired_revision: 1,
        payload: {
          schemaVersion: 1,
          networkId: Opanel::Identifier.external(:network, network.id),
          environmentId: Opanel::Identifier.external(:environment, environment.id),
          clusterId: Opanel::Identifier.external(:cluster, environment.cluster.id)
        },
        request_id: Current.request_id.presence || SecureRandom.uuid,
        correlation_id: Current.correlation_id.presence || SecureRandom.uuid,
        requested_by: actor.id.to_s
      )

      # Create the OutboxEvent (M01-13 pattern).
      OutboxEvent.create!(
        aggregate_type: "Network",
        aggregate_id: network.id,
        event_type: "NetworkCreationRequested",
        schema_version: 1,
        payload: {
          operationId: Opanel::Identifier.external(:operation, operation.id),
          networkId: Opanel::Identifier.external(:network, network.id),
          environmentId: Opanel::Identifier.external(:environment, environment.id)
        },
        occurred_at: Time.current
      )

      # Record in audit trail.
      AuditTrail.record(
        action: :network_created,
        actor: actor,
        resource: network,
        after: network.attributes
      )
    end

    Rails.logger.info(
      event: "ensure_environment_network.created",
      team_id: environment.team.external_id,
      project_id: environment.project.external_id,
      environment_id: environment.external_id,
      network_id: network.external_id,
      operation_id: operation.external_id,
      actor_id: actor.external_id,
      result: "succeeded"
    )

    Opanel::Result.success(network: network, operation: operation)
  end

  def failure(code, message, **details)
    Rails.logger.warn(
      event: "ensure_environment_network.failed",
      team_id: environment&.team&.external_id,
      environment_id: environment&.external_id,
      actor_id: actor&.external_id,
      reason: message
    )

    Opanel::Result.failure(code: code, message: message, details: details)
  end
end
