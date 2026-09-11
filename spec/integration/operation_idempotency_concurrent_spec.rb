require "rails_helper"

# AC5: Idempotency-Key concorrente provado por teste concorrente.
# Múltiplas threads tentam criar operações com a mesma chave; apenas uma sucede.
RSpec.describe "Operation idempotency concurrent", :integration do
  let(:team) { create(:team) }
  let(:service) { create(:service, environment: create(:environment, project: create(:project, team: team))) }
  let(:idempotent_key) { "concurrent-test-#{SecureRandom.hex(16)}" }

  it "only one thread succeeds when multiple threads use the same idempotency key" do
    barrier = Concurrent::CyclicBarrier.new(5)
    results = Concurrent::Array.new
    errors = Concurrent::Array.new

    5.times do |i|
      Thread.new do
        barrier.wait # Coordinate thread start
        begin
          operation = Operation.create!(
            team_id: team.id,
            resource_type: "Service",
            resource_id: service.id,
            type: "UPDATE_SERVICE",
            status: Operation::PENDING,
            desired_revision: (i + 1),
            idempotency_key: idempotent_key,
            payload: { schemaVersion: 1 }
          )
          results << operation
        rescue ActiveRecord::RecordNotUnique => e
          errors << e
        end
      end
    end

    # Wait for all threads
    # Give threads time to complete, but don't block on Thread.list in a tight loop
    sleep 0.1 until results.size + errors.size == 5

    # Exactly one should have succeeded (created the operation)
    # The others get RecordNotUnique errors.
    expect(results.size).to eq(1)
    expect(errors.size).to eq(4)
    expect(errors.all? { |e| e.is_a?(ActiveRecord::RecordNotUnique) }).to be true
  end

  it "concurrent updates to the same service with different keys create separate operations" do
    barrier = Concurrent::CyclicBarrier.new(3)
    operations = Concurrent::Array.new

    3.times do |i|
      Thread.new do
        barrier.wait
        begin
          key = "key-#{i}-#{SecureRandom.hex(8)}"
          op = Operation.create!(
            team_id: team.id,
            resource_type: "Service",
            resource_id: service.id,
            type: "UPDATE_SERVICE",
            status: Operation::PENDING,
            desired_revision: (i + 1),
            idempotency_key: key,
            payload: { schemaVersion: 1 }
          )
          operations << op
        rescue StandardError => e
          # Log but don't fail - we're testing concurrent creation
        end
      end
    end

    sleep 0.1 until operations.size == 3

    # All three operations should have been created with different keys
    expect(operations.size).to eq(3)
    expect(operations.map(&:id).uniq.size).to eq(3)
    expect(Operation.where(resource_id: service.id).count).to eq(3)
  end
end
