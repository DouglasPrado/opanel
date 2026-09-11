require "json"
require "open3"

# HTTP to the Docker Engine API over the local socket — the only transport the
# Swarm Executor has, and the only place in the repository that speaks it.
#
# ## Why the API and not the CLI
#
# `SwarmBootstrap` drives `docker` for a one-off bootstrap, and that is fine for
# a bootstrap. An executor has to say `CONFLICT` when the Service's revision moved
# underneath it (doc 07 §5.3), and `docker service update` cannot: it reads the
# version itself and writes blind. `POST /services/{id}/update?version=N` can,
# and answers `update out of sequence` when it is stale — proved against the lab
# before this file was written.
#
# ## Why `curl`
#
# The Engine speaks HTTP/1.1 over a unix socket, with chunked responses for logs.
# Ruby's `Net::HTTP` does not dial unix sockets, a gem is a dependency this Story
# cannot justify for one transport, and hand-rolling chunked decoding is how a
# subtle bug ends up in the one privileged path. `curl` is a system binary in the
# same sense `docker` already is, handles all of it, and reports connection
# failure and timeout as distinct exit codes — which matters below.
#
# ## Three verbs, no fourth
#
# `get`, `post`, `delete`. There is no method that takes a raw path from outside
# the executor, no method that runs an arbitrary command, and the socket path is
# never an argument: it is resolved from the daemon's own context and refused
# unless it is local (doc 06 §4.2, via `SwarmBootstrap.endpoint`).
#
# ## The one distinction that matters: sent, or not
#
# A request that never reached the daemon can be retried. A mutation whose
# request *was* sent and whose answer was lost cannot — the Engine may have
# applied it (doc 07 §5.3, "Unknown outcome"). `curl` exits 7 when it could not
# connect and 28 when it timed out; a 28 after a successful connect on a mutating
# verb is reported as `unknown`, and everything else that failed before the
# daemon could act is `transient`. The executor turns those into the result the
# reconciler needs.
class EngineClient
  class Error < StandardError
    attr_reader :kind

    def initialize(kind, message)
      @kind = kind
      super(message)
    end

    def transient? = kind == :transient
    def unknown_outcome? = kind == :unknown
  end

  Response = Data.define(:status, :body, :raw) do
    def ok? = status.between?(200, 299)
    def not_found? = status == 404
    def conflict? = status == 409
    def validation? = status == 400
    def server_error? = status >= 500
    def unavailable? = status == 503

    # The Engine's own sentence, from `{"message": …}`. Used for classification
    # and **never** logged verbatim — the caller redacts.
    def message = body.is_a?(Hash) ? body["message"].to_s : ""
  end

  # `api_minimum` in config/architecture/docker-lab.yml. Pinned rather than
  # negotiated per call: a version the platform is developed against is a fact
  # about the platform, not about whichever Engine answered.
  API_VERSION = "v1.44"

  DEFAULT_TIMEOUT_SECONDS = 20
  CONNECT_TIMEOUT_SECONDS = 5

  CURL_COULD_NOT_CONNECT = 7
  CURL_TIMED_OUT = 28

  MUTATING = %w[POST DELETE].freeze

  def initialize(socket: nil, timeout: DEFAULT_TIMEOUT_SECONDS)
    @socket = socket
    @timeout = timeout
  end

  def get(path) = request("GET", path)
  def post(path, body = nil) = request("POST", path, body)
  def delete(path) = request("DELETE", path)

  # Resolved once per client, through the same check the bootstrap uses: a
  # scheme that is not a local socket is refused before any request.
  def socket
    @socket ||= begin
      endpoint = SwarmBootstrap.endpoint
      path = endpoint[%r{\Aunix://(.+)\z}, 1]
      raise Error.new(:transient, "the Docker endpoint #{endpoint.inspect} is not a unix socket") if path.nil?

      path
    end
  end

  private

  def request(method, path, body = nil)
    url = "http://localhost/#{API_VERSION}#{path}"
    arguments = [
      "curl", "--silent", "--show-error", "--unix-socket", socket,
      "--connect-timeout", CONNECT_TIMEOUT_SECONDS.to_s, "--max-time", @timeout.to_s,
      "-X", method, "-H", "Content-Type: application/json",
      "-w", "\n%{http_code}", url
    ]
    arguments.push("--data-binary", "@-") unless body.nil?

    stdout, stderr, status = Open3.capture3(*arguments, stdin_data: body.nil? ? nil : JSON.generate(body))

    return parse(stdout) if status.success?

    raise classify_transport_failure(status.exitstatus, stderr, method)
  rescue Errno::ENOENT
    raise Error.new(:transient, "curl is not on PATH")
  end

  def parse(stdout)
    payload, _, code = stdout.rpartition("\n")
    status = code.to_i
    raise Error.new(:transient, "the Engine returned no HTTP status") if status.zero?

    Response.new(status: status, body: decode(payload), raw: payload)
  end

  def decode(text)
    return nil if text.strip.empty?

    JSON.parse(text)
  rescue JSON::ParserError
    # Logs and pings are not JSON. The raw text is kept on the Response for the
    # one caller that expects it.
    nil
  end

  def classify_transport_failure(exit_code, stderr, method)
    detail = stderr.to_s.lines.first.to_s.strip

    case exit_code
    when CURL_COULD_NOT_CONNECT
      Error.new(:transient, "could not connect to the Docker socket: #{detail}")
    when CURL_TIMED_OUT
      # `curl` reports a connect timeout and a transfer timeout with the same
      # exit code, and — on a unix socket — with the same message: the review
      # reproduced a stalled accept queue and a stalled transfer and both said
      # "Operation timed out after Nms with 0 bytes received". The first version
      # of this branch matched a "Connection timed out" string that this curl
      # never emits, so its "transient" arm was unreachable and its test stubbed
      # a sentence the transport does not produce. There is no honest way to tell
      # the two apart from here, so the conservative answer is the only answer: a
      # timeout on a mutating verb is an unknown outcome, and a timeout on a read
      # is transient because a read cannot have changed anything.
      if MUTATING.include?(method)
        Error.new(:unknown, "the Engine did not answer a #{method} in #{@timeout}s; it may have applied it")
      else
        Error.new(:transient, "the Engine did not answer in #{@timeout}s: #{detail}")
      end
    else
      Error.new(:transient, "curl exited #{exit_code}: #{detail}")
    end
  end
end
