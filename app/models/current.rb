# Request-scoped context that has to travel with the work, not with the caller.
#
# M00-03 needs only the correlation id: it is what ties a job's log line back to
# whatever enqueued it. M00-15 generates a `request_id` at the HTTP edge, seeds the
# correlation id from it, and adds the remaining correlation fields
# (`operation_id`, tenancy, actor) as the Milestones that own them arrive.
class Current < ActiveSupport::CurrentAttributes
  attribute :correlation_id

  # A caller that never set one still gets a usable id, so a log line is never
  # left uncorrelatable.
  def correlation_id
    super || (self.correlation_id = SecureRandom.uuid)
  end
end
