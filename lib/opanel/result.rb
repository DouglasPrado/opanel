# frozen_string_literal: true

module Opanel
  # What a Command answers with.
  #
  # A Command's failure is an outcome, not an exception: "that address is not
  # available" is a thing the caller has to render, not a thing that should
  # unwind the stack. Raising for it would also make the two branches
  # indistinguishable from a genuine defect at the point where the difference
  # matters most.
  #
  # The failure carries the **stable code** of doc 09 §28, so the HTTP status,
  # the message and any future client branching all come from one place. It is
  # deliberately small: there is no base class, no registry and no result monad —
  # a value object with two constructors is the whole requirement.
  class Result
    attr_reader :value, :code, :message, :details

    def self.success(value = nil)
      new(success: true, value: value)
    end

    def self.failure(code:, message:, details: {})
      new(success: false, code: code, message: message, details: details)
    end

    def initialize(success:, value: nil, code: nil, message: nil, details: {})
      @success = success
      @value = value
      @code = code
      @message = message
      @details = details.freeze
      freeze
    end

    def success? = @success
    def failure? = !@success
  end
end
