require "rails_helper"

RSpec.describe Opanel::DatabaseConnection, type: :unit do
  describe ".classify" do
    {
      'FATAL:  password authentication failed for user "opanel"' => :authentication_failed,
      'FATAL:  no pg_hba.conf entry for host "10.0.0.2"' => :authentication_failed,
      'FATAL:  database "opanel_production" does not exist' => :database_missing,
      "could not connect to server: Connection refused" => :host_unreachable,
      "could not translate host name \"db\" to address" => :host_unreachable,
      "timeout expired" => :timeout,
      "something nobody predicted" => :unknown
    }.each do |message, expected|
      it "classifies #{message.inspect} as #{expected}" do
        result = described_class.classify(StandardError.new(message))

        expect(result.cause).to eq(expected)
        expect(result).not_to be_available
      end
    end

    it "classifies a pool checkout timeout as :timeout even without a matching message" do
      result = described_class.classify(ActiveRecord::ConnectionTimeoutError.new("could not obtain a connection"))

      expect(result.cause).to eq(:timeout)
    end

    it "keeps every cause inside the declared vocabulary" do
      causes = [
        "password authentication failed", 'database "x" does not exist',
        "Connection refused", "timeout expired", "invalid connection option", "surprise"
      ].map { |message| described_class.classify(StandardError.new(message)).cause }

      expect(causes).to all(satisfy { |cause| described_class::CAUSES.include?(cause) })
    end
  end

  # A database error message can carry the whole connection string. Nothing here
  # may reach a log, a health response or an archived test artifact.
  describe ".redact" do
    {
      "connection failed: password=hunter2 host=db" =>
        "connection failed: password=[REDACTED] host=db",
      "could not connect to postgres://opanel:s3cr3t@db:5432/opanel_production" =>
        "could not connect to postgres://opanel:[REDACTED]@db:5432/opanel_production",
      'PGPASSWORD=hunter2 was rejected' =>
        "PGPASSWORD=[REDACTED] was rejected"
    }.each do |input, expected|
      it "masks the credential in #{input.inspect}" do
        expect(described_class.redact(input)).to eq(expected)
      end
    end

    it "leaves a message with no credential untouched" do
      message = 'FATAL:  database "opanel_test" does not exist'

      expect(described_class.redact(message)).to eq(message)
    end
  end

  describe "classified detail" do
    it "never carries a password through to the reported detail" do
      error = StandardError.new(
        "connection to server failed: FATAL:  password authentication failed\npassword=hunter2"
      )

      result = described_class.classify(error)

      expect(result.detail).not_to include("hunter2")
      expect(result.cause).to eq(:authentication_failed)
    end

    it "reduces a multi-line PG message to its first line" do
      error = StandardError.new("could not connect to server: Connection refused\n\tis the server running?")

      expect(described_class.classify(error).detail).to eq(
        "StandardError: could not connect to server: Connection refused"
      )
    end
  end
end
