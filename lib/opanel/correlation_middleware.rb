# frozen_string_literal: true

module Opanel
  # Puts the request id into `Current` for the whole request, at the HTTP edge.
  #
  # A controller callback is too late and too narrow: Rails logs "Started GET" and
  # "Completed 200" from `Rails::Rack::Logger`, which runs outside the controller,
  # and an exception handled by the middleware stack never reaches a controller at
  # all. Those are exactly the lines an operator reads first, so the correlation
  # has to be established before them and released after them.
  #
  # `ActionDispatch::RequestId` has already generated the id and will put it in the
  # `X-Request-Id` response header, so the value a user can quote, the value in the
  # log, and the value carried into the job this request enqueues are one value
  # (doc 09 §19).
  #
  # Inserted after `ActionDispatch::Executor`, which is what resets
  # `CurrentAttributes`: setting them before it would have them wiped immediately.
  class CorrelationMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      request_id = env["action_dispatch.request_id"]

      Current.request_id = request_id
      # The correlation id starts as the request id and outlives the response —
      # it travels into the job, and from M01 into the Operation.
      Current.correlation_id = request_id
      Current.source = "http"

      @app.call(env)
    end
  end
end
