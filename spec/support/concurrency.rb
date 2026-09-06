# Concurrency helpers: real threads, real connections, explicit barriers.
#
# Annex D §5.1 requires concurrency to be tested against real PostgreSQL rather
# than reasoned about. A race only reproduces when two writers interleave at the
# exact point that matters, and that interleaving cannot be arranged with `sleep` —
# it has to be forced. A barrier does that: every participant blocks until all of
# them have arrived, so "both read before either wrote" becomes a fact instead of
# a hope.
#
# The Operation Engine's per-resource serialization (M01-16), lease acquisition and
# fencing tokens are all checked with these.
module ConcurrencyHelpers
  class Timeout < StandardError; end

  # Blocks each caller until `expected` callers have arrived. Raising on timeout
  # rather than hanging keeps a broken test from stalling the suite.
  class Barrier
    def initialize(expected, timeout: 10)
      @expected = expected
      @timeout = timeout
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @arrived = 0
    end

    def wait
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout

      @mutex.synchronize do
        @arrived += 1

        if @arrived >= @expected
          @condition.broadcast
        else
          while @arrived < @expected
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise Timeout, "barrier timed out with #{@arrived}/#{@expected} arrived" if remaining <= 0

            @condition.wait(@mutex, remaining)
          end
        end
      end
    end
  end

  def barrier(expected, timeout: 10)
    Barrier.new(expected, timeout: timeout)
  end

  # Runs each block in its own thread with its own Active Record connection, and
  # re-raises the first failure in the calling thread so a failing example reports
  # the real error instead of a silent thread death.
  def concurrently(*blocks)
    threads = blocks.map do |block|
      Thread.new do
        Thread.current.report_on_exception = false
        ActiveRecord::Base.connection_pool.with_connection { block.call }
      end
    end

    threads.map(&:value)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  # A namespace unique to this process and example, so parallel workers cannot
  # collide on a name and a leftover row cannot be mistaken for a fresh one.
  def unique_namespace(prefix = "spec")
    @unique_namespace_counter = (@unique_namespace_counter || 0) + 1

    [ prefix, ENV.fetch("TEST_ENV_NUMBER", "0").presence || "0", Process.pid, @unique_namespace_counter ]
      .join("-")
  end
end

RSpec.configure do |config|
  config.include ConcurrencyHelpers

  # Threads need to see each other's committed rows, so a concurrency example
  # cannot run inside the example's transaction. It cleans up after itself.
  config.around(:each, :concurrent) do |example|
    self.class.use_transactional_tests = false
    example.run
  ensure
    self.class.use_transactional_tests = true
  end
end
