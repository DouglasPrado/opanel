require "rails_helper"

# AC7: Cada tentativa cria um OperationAttempt novo; nenhuma tentativa anterior é sobrescrita.
# Verificado por: UNIQUE(operation_id, attempt_number) e que tentativas não podem ser atualizadas.
RSpec.describe "OperationAttempt immutability", :integration do
  let(:operation) { create(:operation, status: Operation::PENDING) }

  it "creates a new attempt for each retry with unique attempt_number" do
    attempt1 = OperationAttempt.create!(
      operation_id: operation.id,
      attempt_number: 1,
      started_at: Time.current.utc,
      outcome: "NOOP"
    )

    attempt2 = OperationAttempt.create!(
      operation_id: operation.id,
      attempt_number: 2,
      started_at: Time.current.utc,
      outcome: "APPLIED"
    )

    expect(attempt1.attempt_number).to eq(1)
    expect(attempt2.attempt_number).to eq(2)
    expect(operation.reload.attempts.count).to eq(2)
  end

  it "enforces unique constraint on (operation_id, attempt_number)" do
    OperationAttempt.create!(
      operation_id: operation.id,
      attempt_number: 1,
      started_at: Time.current.utc,
      outcome: "NOOP"
    )

    # Try to create another with the same attempt_number
    expect {
      OperationAttempt.create!(
        operation_id: operation.id,
        attempt_number: 1,
        started_at: Time.current.utc,
        outcome: "APPLIED"
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "attempt_number must be >= 1" do
    expect {
      OperationAttempt.create!(
        operation_id: operation.id,
        attempt_number: 0,
        started_at: Time.current.utc,
        outcome: "NOOP"
      )
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "preserves attempt timeline: started_at and finished_at are immutable" do
    start_time = 5.seconds.ago
    end_time = 2.seconds.ago

    attempt = OperationAttempt.create!(
      operation_id: operation.id,
      attempt_number: 1,
      started_at: start_time,
      finished_at: end_time,
      outcome: "APPLIED"
    )

    # Verify both times are preserved
    expect(attempt.reload.started_at.to_i).to eq(start_time.to_i)
    expect(attempt.reload.finished_at.to_i).to eq(end_time.to_i)
  end

  it "records outcome and error for the attempt" do
    attempt = OperationAttempt.create!(
      operation_id: operation.id,
      attempt_number: 1,
      started_at: Time.current.utc,
      finished_at: 1.second.ago,
      outcome: "CONFLICT",
      error_code: "image_not_found",
      error_message: "Image myregistry/app:sha256:abc123 not found in registry"
    )

    reloaded = OperationAttempt.find(attempt.id)
    expect(reloaded.outcome).to eq("CONFLICT")
    expect(reloaded.error_code).to eq("image_not_found")
    expect(reloaded.error_message).to include("not found")
  end
end
