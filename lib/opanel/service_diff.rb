# The diff between a Service's Desired State and what the Swarm actually holds
# (doc 07 §11.4, M01-18 AC4).
#
# ## A pure function
#
# `compute` reads values and returns a value. It opens no connection, writes no
# column and decides no authorization. The caller decides whether and how to
# apply what it returns — which is what makes the classification testable
# without a daemon, and what keeps step 4 of doc 07 §11.3 free of side effects.
#
# ## Only the classes this Story can apply
#
# `NOOP`, `CREATE`, `UPDATE_SAFE`, `ROLLOUT`, `BLOCKED`. `DELETE` is M02-09 and
# `DRIFT` is M02-06, so neither is a constant here. `lib/opanel/network_diff.rb`
# shipped a `BLOCKED` branch reachable only at create time, and the arbitration
# that recorded it told this Story not to repeat the shape: every class below is
# decided by an input a test can produce, and `spec/unit/service_diff_spec.rb`
# produces each one.
#
# ## What the observation can and cannot show
#
# ADR-0009 §2 fixes the service attribute allowlist at `image`, `replicas` and
# `mode` — deliberately, because container `Env` values must never cross into
# the domain. So a change to args, env, resources, placement or healthcheck is
# **invisible** in the observation. The ownership label
# `com.opanel.desired_revision` carries the revision that was applied, and a
# revision that moved with image and replicas unchanged is read as a spec change
# this module cannot see. The safe reading of an unseen change is `ROLLOUT` —
# the class that replaces tasks — never `NOOP`.
#
# ## What it deliberately does not classify
#
# A Swarm `Spec.Name` is immutable, so a name that no longer matches the derived
# technical name cannot be converged by any operation this Story owns. That is
# drift, and drift is M02-06. Classifying it here would produce a class the
# reconciler cannot apply, which is the same defect in a different place.
module Opanel
  class ServiceDiff
    NOOP = ReconciliationRun::NOOP
    CREATE = ReconciliationRun::CREATE
    UPDATE_SAFE = ReconciliationRun::UPDATE_SAFE
    ROLLOUT = ReconciliationRun::ROLLOUT
    BLOCKED = ReconciliationRun::BLOCKED_CLASS

    # A placement constraint is interpolated into a Swarm spec. Anything that is
    # not `key==value` / `key!=value` is refused rather than passed through.
    CONSTRAINT_FORMAT = /\A[a-zA-Z0-9_.\-]+(?:==|!=)[a-zA-Z0-9_.\-\/]+\z/

    attr_reader :diff_class, :error_reason, :actions_to_apply

    # @param service [Service] the Desired State
    # @param desired_image [String, nil] the digest-pinned reference the
    #   translator produced, or nil when the Service is not pinned (AC2)
    # @param network [Network, nil] the Environment's overlay network
    # @param actual [Opanel::RuntimeObservation, nil] never Engine JSON
    def self.compute(service:, desired_image:, network:, actual:)
      new(service: service, desired_image: desired_image, network: network, actual: actual).compute
    end

    def initialize(service:, desired_image:, network:, actual:)
      @service = service
      @desired_image = desired_image
      @network = network
      @actual = actual
      @actions_to_apply = []
    end

    def compute
      blocker = first_blocker
      return blocked(blocker) if blocker

      return create if @actual.nil?

      classify_update
    end

    private

    # The three reasons the platform refuses to act, all decided from input
    # alone and all reachable: an image it cannot pin, a network it cannot
    # attach to, and a placement it will not send.
    def first_blocker
      if @desired_image.blank?
        return "The image #{@service.image_ref.inspect} is not pinned to a digest. " \
               "Deploys reference an immutable digest, never a mutable tag."
      end

      if @network.nil? || @network.swarm_network_id.blank? || @network.status != Network::READY
        return "The Environment's overlay network has not converged, so there is nothing to attach " \
               "the Service to. The network reconciles first."
      end

      invalid = Array(@service.constraints).reject { |c| c.to_s.match?(CONSTRAINT_FORMAT) }
      return nil if invalid.empty?

      "A placement constraint is not in `key==value` form and was not sent to the Engine."
    end

    def create
      @diff_class = CREATE
      @actions_to_apply = [ { action: "create", name: @service.technical_name } ]
      self
    end

    def blocked(reason)
      @diff_class = BLOCKED
      @error_reason = reason
      self
    end

    def classify_update
      unless Opanel::Ownership.managed_by_platform?(@actual)
        return blocked(
          "A Swarm Service named #{@actual.name.inspect} carries this Service's ownership label but is " \
          "not managed by the platform — its identifiers do not resolve. It is never adopted and never " \
          "removed automatically."
        )
      end

      if image_changed?
        update(ROLLOUT, "image")
      elsif replicas_changed?
        update(UPDATE_SAFE, "replicas")
      elsif revision_changed?
        update(ROLLOUT, "revision")
      else
        @diff_class = NOOP
        self
      end
    end

    def update(diff_class, field)
      @diff_class = diff_class
      @actions_to_apply = [ { action: "update", name: @service.technical_name, changed: field } ]
      self
    end

    def image_changed? = @actual.attributes["image"].to_s != @desired_image.to_s

    def replicas_changed? = @actual.attributes["replicas"].to_i != @service.replicas.to_i

    def revision_changed?
      applied = @actual.labels["#{Opanel::Ownership::NAMESPACE}.desired_revision"]
      applied.to_s != @service.desired_revision.to_s
    end
  end
end
