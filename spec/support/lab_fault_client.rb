# Fault injection between the Engine and the executor, for the distributed
# failures M01-18 has to prove rather than argue (AC5, AC7).
#
# It wraps the **real** `EngineClient`: the request reaches the daemon and the
# daemon does the work, and only the *answer* is lost or the process is killed
# afterwards. That is the whole point — the cases that matter are the ones where
# the effect happened and the caller does not know it. A stubbed executor could
# not reproduce them, because the resource would not actually exist.
class LabFaultClient
  attr_reader :calls

  # @param after [String] "METHOD /path-prefix" — the call after which the fault fires
  # @param fault [Symbol] :unknown (a lost answer) or :crash (the worker dies)
  # @param times [Integer] how many times the fault fires before the client behaves
  def initialize(inner: EngineClient.new, after:, fault: :unknown, times: 1)
    @inner = inner
    @after = after
    @fault = fault
    @remaining = times
    @calls = []
  end

  def get(path) = dispatch("GET", path) { @inner.get(path) }
  def delete(path) = dispatch("DELETE", path) { @inner.delete(path) }
  def post(path, body = nil) = dispatch("POST", path) { @inner.post(path, body) }

  def paths = @calls.map { |method, path| "#{method} #{path.split('?').first}" }

  private

  def dispatch(method, path)
    @calls << [ method, path ]
    response = yield

    return response unless fires?(method, path)

    @remaining -= 1
    case @fault
    when :unknown then raise EngineClient::Error.new(:unknown, "the answer was lost after the Engine applied it")
    when :crash then raise LabFaultClient::WorkerDied, "the worker died after the Engine applied the change"
    end
  end

  def fires?(method, path)
    @remaining.positive? && "#{method} #{path}".start_with?(@after)
  end

  class WorkerDied < StandardError; end
end

# The other distributed failure: somebody else moved the resource between the
# observation and the write (M01-18 AC6).
#
# It cannot be arranged with a stub, because the whole question is what the
# **Engine** does with a `Version.Index` that is no longer current. So the
# interference is real: a block runs against the daemon immediately before the
# matching call, the runtime version moves, and the update the reconciler had
# already composed arrives stale.
class LabRacingClient
  attr_reader :calls, :interfered

  def initialize(inner: EngineClient.new, before:, &interference)
    @inner = inner
    @before = before
    @interference = interference
    @interfered = false
    @calls = []
  end

  def get(path) = dispatch("GET", path) { @inner.get(path) }
  def delete(path) = dispatch("DELETE", path) { @inner.delete(path) }
  def post(path, body = nil) = dispatch("POST", path) { @inner.post(path, body) }

  private

  def dispatch(method, path)
    if !@interfered && "#{method} #{path}".start_with?(@before)
      @interfered = true
      @interference.call
    end

    @calls << [ method, path ]
    yield
  end
end
