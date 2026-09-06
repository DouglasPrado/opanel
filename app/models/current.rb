# Request-scoped context that travels with the work rather than with the caller.
#
# Everything here is a correlation identifier: it exists so a line in the log, a
# job execution and a user-visible error can be tied to the same request without
# anyone reproducing it (Annex I §19.2).
#
# The fields beyond `request_id` and `correlation_id` are **reserved** for the
# Milestones that own them — `operation_id` from M01's Operation Engine, the
# tenancy chain from M01's entities, `actor_id` from M01's authentication. They
# are declared now so the logger's contract does not change when those Stories
# start setting them, and they are simply absent from a log line until then.
class Current < ActiveSupport::CurrentAttributes
  attribute :request_id
  attribute :correlation_id

  # Reserved. See above.
  attribute :operation_id
  attribute :team_id
  attribute :project_id
  attribute :environment_id
  attribute :service_id
  attribute :cluster_id
  attribute :node_id
  attribute :actor_id
  attribute :source

  # A caller that never set one still gets a usable id, so a log line is never
  # left uncorrelatable. At an HTTP boundary this is the request id Rails
  # generated; in a job it is the id the enqueuing request carried.
  def correlation_id
    super || (self.correlation_id = SecureRandom.uuid)
  end
end
