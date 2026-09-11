# The Service reconciler's two triggers (doc 07 §11.2, §23, M01-18).
#
# ## The sweep is the guarantee; the Operation is the accelerator
#
# `perform(operation_id)` reconciles one Service because an operator asked for
# something. `perform` with no argument sweeps: it picks up Operations nobody
# consumed, then every Service whose applied revision is behind its desired one,
# then the converged ones, more slowly. Correctness comes from re-reading state,
# never from an uninterrupted stream of events.
#
# ## Why the trigger lives here and not in a Command
#
# `PublishPendingOutboxEvents` enqueues `OutboxEventConsumerJob`, a class this
# repository does not define (M01-14 debt, recorded in the Story report). Until
# that consumer exists there is no path from an OutboxEvent to a worker, so the
# sweep claims unconsumed Operations itself. `app/commands/**` is outside this
# Story's boundary and is not touched to paper over it.
#
# ## Supersession is decided before any Engine call
#
# When several Operations are open for one Service, only the newest revision is
# reconciled; the older ones are `SUPERSEDED` rather than applied (doc 07 §6,
# M01-18 AC8). Stale configuration is never sent to the Engine.
class ReconcileServicesJob < ApplicationJob
  queue_as :system

  BATCH = 100

  def perform(operation_id = nil)
    operation_id ? reconcile_operation(operation_id) : sweep
  end

  private

  def reconcile_operation(operation_id)
    # rubocop:disable Opanel/UnscopedTenantQuery -- M01-18: a worker has no actor to scope by. The
    # Operation row itself carries the tenancy, and the reconciler reads the Team from the Service it
    # names; there is no route, no request and nothing for a caller to substitute.
    operation = Operation.find_by(id: operation_id)
    # rubocop:enable Opanel/UnscopedTenantQuery
    return if operation.nil? || operation.terminal?

    service = service_for(operation)
    return if service.nil?

    supersede_older(service, operation)
    return if operation.reload.terminal?

    claim(operation)
    ServiceReconciler.call(service: service, trigger: ReconciliationRun::OPERATION, operation: operation)
  end

  def sweep
    open_operations.find_each { |operation| guarded(operation.resource_id) { reconcile_operation(operation.id) } }

    Service.kept.where(status: reconcilable_statuses).where(unconverged).limit(BATCH).find_each do |service|
      guarded(service.id) { ServiceReconciler.call(service: service, trigger: ReconciliationRun::PERIODIC) }
    end
  end

  # Services whose runtime the platform is responsible for. A DRAFT Service has
  # never been asked for, and a DELETING one belongs to M02-09.
  def reconcilable_statuses = [ Service::PROVISIONING, Service::RUNNING, Service::DEGRADED ]

  def unconverged = "applied_revision IS NULL OR applied_revision < desired_revision"

  def open_operations
    Operation.where(resource_type: "Service", type: %w[UPDATE_SERVICE CREATE_SERVICE])
      .where(status: [ Operation::PENDING, Operation::QUEUED ])
      .order(:created_at)
      .limit(BATCH)
  end

  # The Operation names a resource id and carries its own `team_id`. Following
  # the id without checking the Team is the "fetch by ID and then trust the
  # route for tenancy" failure in a worker: an Operation row whose `resource_id`
  # points at another Team's Service would reconcile that Service under this
  # Operation's authority. The Command that wrote the Operation authorized one
  # Team; the join here is what makes the worker respect it.
  def service_for(operation)
    # rubocop:disable Opanel/UnscopedTenantQuery -- M01-18: a worker has no actor, so there is no
    # `TenantScope.for(actor, …)` to route through. The Team the cop exists to protect is applied
    # explicitly on the line below, which is the same guarantee by the other spelling.
    Service.kept.where(team_id: operation.team_id).find_by(id: operation.resource_id)
    # rubocop:enable Opanel/UnscopedTenantQuery
  end

  # Only the newest open Operation for a Service is applied (AC8).
  def supersede_older(service, operation)
    newest = open_operations.where(team_id: service.team_id, resource_id: service.id)
      .max_by(&:desired_revision)
    return if newest.nil? || newest.desired_revision <= operation.desired_revision

    operation.mark_superseded!
    Rails.logger.info(
      event: "service.reconciliation.operation_superseded",
      service_id: service.external_id,
      operation_id: operation.external_id,
      superseded_revision: operation.desired_revision,
      target_revision: newest.desired_revision
    )
  end

  # The Operation is claimed but left QUEUED: the reconciler moves it to RUNNING
  # only when it decides to apply, so a revision superseded in between reaches
  # SUPERSEDED by the transition doc 07 §5.2 allows.
  def claim(operation)
    return unless operation.status == Operation::PENDING

    operation.update!(status: Operation::QUEUED)
  end

  def guarded(resource_id)
    yield
  rescue StandardError => error
    # One Service's failure never stops the batch. The sweep runs again.
    Rails.logger.error(
      event: "reconcile_services_job.failed",
      resource_id: resource_id,
      error_class: error.class.name,
      error_message: error.message.lines.first
    )
  end
end
