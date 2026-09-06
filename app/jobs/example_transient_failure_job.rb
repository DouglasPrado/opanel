# Example job that always fails transiently, so the retry ceiling is observable.
#
# It proves that a job retries according to *its own* policy and then stops. There
# is no global retry policy to fall back on, and nothing here retries forever.
class ExampleTransientFailureJob < ApplicationJob
  class TransientBoom < StandardError; end

  queue_as Opanel::Queues::SYSTEM

  # Three attempts total, then a recorded terminal failure. `jitter: 0` keeps the
  # backoff deterministic so a test can assert timing without becoming flaky.
  retry_policy on: TransientBoom, attempts: 3, wait: 0.seconds, jitter: 0.0

  def perform(name:)
    raise InvalidPayload, "name must be a String" unless name.is_a?(String)

    # The counter records how many times the job actually ran, so the retry ceiling
    # is checked against an effect rather than against a log line.
    InfrastructureCheckpoint.converge!(name).count_execution!

    raise TransientBoom, "this job always fails transiently, on purpose"
  end
end
