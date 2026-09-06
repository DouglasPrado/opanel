# frozen_string_literal: true

module RuboCop
  module Cop
    module Opanel
      # Annex I §7.1: never rescue `StandardError`/`Exception` broadly and return success.
      #
      # A broad rescue that answers with a truthy value turns a failure into a
      # silent no-op. The caller believes the work happened, the reconciler
      # believes Actual State converged, and the defect surfaces somewhere with no
      # connection to its cause.
      #
      # Observing a failure and re-raising is fine. Classifying it into a result
      # object that the caller must inspect is fine. Answering `true` is not.
      #
      # @example
      #   # bad
      #   def deploy
      #     executor.update_service(...)
      #   rescue StandardError
      #     true
      #   end
      #
      #   # good — re-raised after being observed
      #   def deploy
      #     executor.update_service(...)
      #   rescue StandardError => error
      #     log_failure(error)
      #     raise
      #   end
      #
      #   # good — classified into a result the caller has to look at
      #   def check
      #     pool.with_connection { ... }
      #     Result.new(cause: :available)
      #   rescue StandardError => error
      #     classify(error)
      #   end
      class SilentRescue < Base
        MSG = "Broad rescue returns success. Re-raise, or return a classified failure the caller " \
              "must inspect (Annex I §7.1)."

        BROAD_EXCEPTIONS = %w[StandardError Exception].freeze

        def on_resbody(node)
          return unless broad?(node)

          body = node.body
          return if body.nil? # Lint/SuppressedException owns the empty case
          return if reraises?(body)
          return unless returns_success?(body)

          add_offense(node)
        end

        private

        # A bare `rescue`, or one naming StandardError/Exception explicitly.
        def broad?(node)
          exceptions = node.children.first
          return true if exceptions.nil?

          exceptions.children.any? do |exception|
            exception.const_type? && BROAD_EXCEPTIONS.include?(exception.const_name)
          end
        end

        def reraises?(body)
          each_expression(body).any? { |expression| expression.send_type? && expression.method?(:raise) }
        end

        # The value the rescue answers with. A truthy literal reads as "it worked".
        def returns_success?(body)
          last = each_expression(body).to_a.last
          return false if last.nil?

          case last.type
          when :true, :str, :sym, :int, :float then true
          when :array, :hash then true
          else false
          end
        end

        def each_expression(body)
          return enum_for(:each_expression, body) unless block_given?

          if body.begin_type?
            body.children.each { |child| yield child }
          else
            yield body
          end
        end
      end
    end
  end
end
