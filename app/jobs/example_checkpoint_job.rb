# Example job that makes the two halves of "safe to re-run" observable in one run.
#
# - **Effect:** the checkpoint row named `name` is created if it is missing. The
#   unique index is what makes this idempotent — re-running converges instead of
#   duplicating.
# - **Witness:** the row's counter is incremented on every execution. It is
#   deliberately *not* idempotent, so a test can tell "ran twice, applied once"
#   apart from "ran once".
#
# It exists to prove the delivery mechanism, not to model anything: M00 implements
# no Opanel domain. A real job hands off to a Command instead of writing here.
class ExampleCheckpointJob < ApplicationJob
  queue_as Opanel::Queues::SYSTEM

  # Deadlocks and serialization failures are the transient conditions a write of
  # this shape can actually hit under concurrency.
  retry_policy on: [ ActiveRecord::Deadlocked, ActiveRecord::SerializationFailure ],
    attempts: 3,
    wait: 1.second

  NAME_FORMAT = /\A[a-z0-9][a-z0-9-]{0,62}\z/

  # `hold_seconds` keeps the job inside `perform` long enough for a test to kill
  # the worker mid-execution.
  def perform(name:, hold_seconds: 0)
    validate!(name, hold_seconds)

    sleep(hold_seconds) if hold_seconds.positive?

    checkpoint = InfrastructureCheckpoint.converge!(name)
    checkpoint.count_execution!

    checkpoint
  end

  private

  # Active Job already refuses to deserialize arbitrary classes; this adds the
  # shape check the job itself depends on, before any effect is applied.
  def validate!(name, hold_seconds)
    unless name.is_a?(String) && name.match?(NAME_FORMAT)
      raise InvalidPayload, "name must match #{NAME_FORMAT.inspect}"
    end

    unless hold_seconds.is_a?(Numeric) && hold_seconds >= 0 && hold_seconds <= 30
      raise InvalidPayload, "hold_seconds must be a number between 0 and 30"
    end
  end
end
