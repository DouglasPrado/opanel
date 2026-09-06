# frozen_string_literal: true

module RuboCop
  module Cop
    module Opanel
      # Annex I §7.1: errors are typed and classified when the class changes retry,
      # status or the response to the client.
      #
      # `raise "something went wrong"` produces a `RuntimeError`. Nothing upstream
      # can branch on it: a retry policy cannot tell a transient failure from a
      # permanent one, an API cannot map it to a stable error code, and a job
      # cannot decide between retrying and discarding. The message is for a human;
      # the class is for the program.
      #
      # @example
      #   # bad
      #   raise "service #{id} is not ready"
      #
      #   # good
      #   raise ServiceNotReady, "service #{id} is not ready"
      class UnclassifiedError < Base
        MSG = "Raise a classified error class instead of a bare message — retry, status and the " \
              "client response all branch on the class (Annex I §7.1)."

        RESTRICT_ON_SEND = %i[raise fail].freeze

        def on_send(node)
          return unless node.receiver.nil?

          first = node.first_argument
          return if first.nil?
          return unless first.type?(:str, :dstr)

          add_offense(node)
        end
      end
    end
  end
end
