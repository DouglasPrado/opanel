# Captures everything written through Rails.logger for the duration of a block.
#
# Assertions about observability belong in the suite: "the operation is
# diagnosable from the log" is a requirement, not a side effect, so it is checked
# the same way behaviour is.
module LogCapture
  def capture_logs
    buffer = StringIO.new
    previous = Rails.logger

    Rails.logger = ActiveSupport::Logger.new(buffer).tap do |logger|
      logger.level = :debug
      # The application's own formatter, not the default: structure and redaction
      # are the things under test, and a plain buffer would have neither.
      logger.formatter = Rails.application.config.log_formatter
    end
    yield
    buffer.string
  ensure
    Rails.logger = previous
  end
end

RSpec.configure do |config|
  config.include LogCapture
end
