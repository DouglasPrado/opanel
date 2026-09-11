# Periodically observes all active Services and persists observations.
#
# This job runs on a cadence (configured in config/recurring.yml) and reads
# actual state from Swarm for each Service that has converged (swarm_service_id
# is set). Observations are append-only and immutable.
#
# This is the guarantee of doc 07 §11.2: "correctness comes from re-reading
# state, not from trusting an uninterrupted event stream".
class ObserveServicesJob < ApplicationJob
  queue_as :default

  # Run without delay; it is scheduled periodically by Solid Queue.
  self.wait = 0

  def perform
    # Observe all Services that have been provisioned.
    services = Service.where("swarm_service_id IS NOT NULL").kept

    services.each do |service|
      observe_service(service)
    end

    Rails.logger.info "ObserveServicesJob completed: observed #{services.count} services"
  rescue StandardError => e
    Rails.logger.error "ObserveServicesJob failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}"
    # Do not re-raise; a temporary failure should not block the next sweep.
  end

  private

  def observe_service(service)
    result = ObserveService.call(service: service)

    if result.success?
      Rails.logger.debug "Observed service #{service.id}: #{result.observation.desired_tasks} desired, #{result.observation.running_tasks} running"
    else
      Rails.logger.warn "Failed to observe service #{service.id}: #{result.code} - #{result.message}"
    end
  rescue StandardError => e
    Rails.logger.error "Error observing service #{service.id}: #{e.class} #{e.message}"
  end
end
