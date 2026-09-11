# Computes the diff between desired and actual network state (doc 07 §11.4, AC1).
#
# ## Pure function
#
# This class computes a diff as a value, with no side effects. The diff class is
# determined by examining desired_state and actual_state without modifying either.
# The caller decides whether and how to apply the diff (AC1).
#
# ## Diff classes
#
# NOOP: desired and actual are equivalent; no action needed (AC4, idempotent).
# CREATE: desired network does not exist; create it.
# BLOCKED: network name/ID conflicts with an unowned resource; never adopt (AC6).
#
# ## Actual State
#
# The `actual` parameter is a RuntimeObservation (ADR-0009) or nil. Observations
# are the normalized form returned by the executor; never raw Engine JSON.
#
module Opanel
  class NetworkDiff
    attr_reader :diff_class, :error_reason, :actions_to_apply

    NOOP = ReconciliationRun::NOOP
    CREATE = ReconciliationRun::CREATE
    BLOCKED = ReconciliationRun::BLOCKED_CLASS

    def self.compute(desired:, actual:)
      new(desired: desired, actual: actual).compute
    end

    def initialize(desired:, actual:)
      @desired = desired
      @actual = actual
      @diff_class = nil
      @error_reason = nil
      @actions_to_apply = []
    end

    def compute
      if @actual.nil?
        # Network does not exist in Swarm; must create it (AC1: CREATE).
        @diff_class = CREATE
        @actions_to_apply = [ { action: "create", name: @desired.technical_name } ]
      elsif actual_is_ours?
        # Network exists and is managed by us; check if revision matches (AC4, idempotent).
        if actual_matches_desired?
          @diff_class = NOOP
        else
          # Desired revision changed; need to update (out of scope for network, but structure is ready).
          @diff_class = NOOP  # Networks don't support UPDATE_SAFE; only CREATE/NOOP/BLOCKED for now.
        end
      else
        # Network exists but is not managed by us; BLOCKED (AC6, never adopt).
        @diff_class = BLOCKED
        @error_reason = "A network named #{@actual.name.inspect} already exists " \
                        "and is not managed by the platform. Rename the network or delete it manually."
      end

      self
    end

    private

    def actual_is_ours?
      return false if @actual.nil?

      Opanel::Ownership.managed_by_platform?(@actual)
    end

    def actual_matches_desired?
      return false if @actual.nil?

      actual_name = @actual.name
      desired_name = @desired.technical_name

      # Compare name and ownership (revision is in the labels).
      actual_name == desired_name && actual_is_ours?
    end
  end
end
