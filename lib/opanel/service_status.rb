# Derives the presented Service status from appliedRevision and observation.
#
# Status is NEVER stored as a manual boolean. It is always calculated from:
# 1. Whether the applied revision matches the desired revision (convergence)
# 2. The observation of actual state (task counts, health)
# 3. The age of the observation (staleness)
#
# This is a pure function; all inputs are provided explicitly.
module Opanel::ServiceStatus
  # Service status vocabulary (doc 07 §17.1, derivable in M01).
  # DRIFTED and PAUSED arrive in M02-06 and future milestones.
  PENDING   = "PENDING"     # Desired state exists but not applied yet
  DEPLOYING = "DEPLOYING"   # Operation mutant/rollout in progress
  HEALTHY   = "HEALTHY"     # Applied revision = desired, all replicas healthy
  DEGRADED  = "DEGRADED"    # Partially functional or tasks unhealthy
  FAILED    = "FAILED"      # Desired state did not converge (last attempt failed)

  PRESENTED_STATUSES = [ PENDING, DEPLOYING, HEALTHY, DEGRADED, FAILED ].freeze

  # Stale observation threshold: 5 minutes (300 seconds).
  # After this, the observation is marked stale and HEALTHY is not declared.
  STALE_THRESHOLD_SECONDS = 300

  # Derives the Service status from applied/desired revision and observation.
  #
  # @param desired_revision [Integer] the desired revision the user wants
  # @param applied_revision [Integer, nil] the revision last observed converged
  # @param observation [ServiceObservation, nil] the latest observation from Swarm
  # @param observed_at_timestamp [Time] current time for staleness calculation
  # @return [String] one of the PRESENTED_STATUSES
  def self.derive(desired_revision:, applied_revision:, observation:, observed_at_timestamp: Time.current)
    # No observation at all: show PENDING (desired state not yet observed).
    return PENDING if observation.nil?

    # Observation is stale: show FAILED (we can't declare healthy without fresh data).
    if stale?(observation, observed_at_timestamp)
      return FAILED
    end

    # If applied revision < desired revision, a deployment is in progress.
    if applied_revision.nil? || applied_revision < desired_revision
      return DEPLOYING
    end

    # Applied equals desired: check health of the observation.
    if applied_revision == desired_revision
      return status_from_observation(observation)
    end

    # Safety: should not reach here, but if applied > desired, show FAILED.
    FAILED
  end

  # Determines staleness of an observation.
  # @param observation [ServiceObservation] the observation to check
  # @param observed_at_timestamp [Time] current time
  # @return [Boolean] true if observation is older than STALE_THRESHOLD_SECONDS
  def self.stale?(observation, observed_at_timestamp)
    return true if observation.nil?
    (observed_at_timestamp - observation.observed_at) > STALE_THRESHOLD_SECONDS
  end

  # Derives status from observation when applied revision = desired revision.
  # @param observation [ServiceObservation]
  # @return [String] one of HEALTHY, DEGRADED
  private_class_method def self.status_from_observation(observation)
    # All desired tasks running and healthy = HEALTHY.
    # (In M02, readiness probes and metrics will refine this.)
    if observation.running_tasks == observation.desired_tasks &&
       observation.healthy_tasks == observation.desired_tasks &&
       observation.failed_tasks == 0

      HEALTHY
    else
      # Partial failure, health mismatch, or tasks not yet running.
      DEGRADED
    end
  end
end
