class ApplicationJob < ActiveJob::Base
  # A payload the job cannot trust is a defect, not a transient condition. It is
  # discarded rather than retried: retrying malformed input just burns the queue.
  class InvalidPayload < StandardError; end

  # The declared retry policy of this job class, or nil when it declares none.
  # There is deliberately no global default: a job that has not thought about its
  # own failure modes does not retry (Annex I §7.1 — do not hide failures behind
  # blanket retries).
  class_attribute :declared_retry_policy, instance_accessor: false, default: nil

  # Declarative per-class retry policy.
  #
  #   retry_policy on: Timeout::Error, attempts: 5, wait: :polynomially_longer
  #
  # `attempts` is a hard ceiling: when it is reached the job fails terminally and
  # the failure is recorded. Never infinite.
  def self.retry_policy(on:, attempts:, wait: :polynomially_longer, jitter: 0.15)
    raise ArgumentError, "attempts must be a positive integer" unless attempts.is_a?(Integer) && attempts.positive?

    errors = Array(on)
    self.declared_retry_policy = { on: errors, attempts: attempts, wait: wait, jitter: jitter }.freeze

    errors.each do |error_class|
      retry_on error_class, attempts: attempts, wait: wait, jitter: jitter do |job, error|
        job.record_terminal_failure(error)
      end
    end
  end

  discard_on(InvalidPayload) { |job, error| job.record_discarded_payload(error) }

  around_perform :with_correlation_context

  # Captured from the enqueuing context and carried through serialization, so the
  # job's log line points back at whatever asked for the work.
  def correlation_id
    @correlation_id ||= Current.correlation_id
  end

  # The HTTP request that enqueued this job, when there was one.
  #
  # Carried separately from `correlation_id` rather than folded into it. They are
  # the same value at an HTTP boundary and diverge everywhere else: a job
  # enqueued by a scheduler or by another job has a correlation id and no
  # request. M00-15 AC2 asks for the request id by name in the log line of the
  # job *that request enqueued*, so it has to survive the queue — reading
  # `Current.request_id` inside `perform` finds nothing, because the request
  # ended long before the worker picked the job up.
  #
  # `defined?` rather than `||=`: nil is the correct answer for a job with no
  # request behind it, and re-reading `Current` on every call would let a worker
  # attribute one job to another job's request.
  def request_id
    return @request_id if defined?(@request_id)

    @request_id = Current.request_id
  end

  attr_writer :correlation_id, :request_id

  def serialize
    super.merge("correlation_id" => correlation_id, "request_id" => request_id)
  end

  def deserialize(job_data)
    super
    self.correlation_id = job_data["correlation_id"]
    self.request_id = job_data["request_id"]
  end

  def record_terminal_failure(error)
    log(event: "job.failed_terminally", result: "failed", error_class: error.class.name)
  end

  def record_discarded_payload(error)
    log(event: "job.discarded_invalid_payload", result: "discarded", error_class: error.class.name)
  end

  private

  def with_correlation_context
    Current.set(correlation_id: correlation_id, request_id: request_id) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        yield
        log(event: "job.performed", result: "ok", duration_ms: elapsed_ms(started))
      rescue StandardError => error
        # Re-raised immediately: this observes the failure, it does not swallow it.
        log(event: "job.failed", result: "error", duration_ms: elapsed_ms(started), error_class: error.class.name)
        raise
      end
    end
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  # A Hash is passed to the logger rather than an interpolated string so the
  # structured sink of M00-15 can emit these as fields without re-parsing.
  #
  # Arguments are never logged: a job payload may reference a SecretVersion, and
  # the log is not the place to find out.
  def log(event:, result:, **fields)
    Rails.logger.info(
      {
        event: event,
        job_class: self.class.name,
        job_id: job_id,
        queue: queue_name,
        attempt: executions + 1,
        result: result,
        correlation_id: correlation_id
      }.merge(fields)
    )
  end
end
