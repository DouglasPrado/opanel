require "rails_helper"

# AC12: Crash simulado entre COMMIT e publicação não perde a intenção.
# Este é o teste que justifica o Outbox (doc 07 §10).
RSpec.describe "Operation outbox crash recovery", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }
  let(:actor) { team.team_members.first.user }

  it "survives a crash between transaction commit and queue publish" do
    # Crash happens AFTER the transaction commits (simulate by raising after call returns)
    allow_any_instance_of(UpdateServiceDesiredState).to receive(:call).and_wrap_original do |method|
      method.call  # executes persist, creates rows inside transaction
      raise "Simulated crash in queue publish"
    end

    # The crash happens AFTER the transaction commits
    expect {
      UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5
      )
    }.to raise_error("Simulated crash in queue publish")

    # Despite the crash, the operation and outbox event were persisted atomically
    expect(Operation.where(resource_id: service.id).count).to eq(1)
    expect(OutboxEvent.where(aggregate_id: service.id).count).to eq(1)

    operation = Operation.where(resource_id: service.id).last
    expect(operation.status).to eq(Operation::PENDING)

    event = OutboxEvent.where(aggregate_id: service.id).last
    expect(event.published_at).to be_nil # Not yet published due to crash

    # M01-14 dispatcher sweep will recover this unpublished event
  end

  it "idempotent key prevents duplicates even if the command is retried after crash" do
    idempotent_key = SecureRandom.uuid

    # First attempt succeeds, but then crash happens after commit
    allow_any_instance_of(UpdateServiceDesiredState).to receive(:call).and_wrap_original do |method|
      method.call  # executes persist, creates operation and outbox event inside transaction
      raise "Simulated crash after commit"
    end

    expect {
      UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5,
        idempotency_key: idempotent_key
      )
    }.to raise_error("Simulated crash after commit")

    # The first operation was persisted despite the crash
    first_operation = Operation.where(resource_id: service.id).last
    expect(first_operation.idempotency_key).to eq(idempotent_key)
    expect(first_operation.status).to eq(Operation::PENDING)

    # Clear the stub to allow normal operation
    allow_any_instance_of(UpdateServiceDesiredState).to receive(:call).and_call_original

    # Retry with the same key should use the existing operation (idempotent)
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5,
      idempotency_key: idempotent_key
    )

    # Should get back the same operation via idempotency key
    expect(result).to be_success
    expect(result.value[:operation_id]).to eq(first_operation.external_id)

    # Verify no second operation was created
    expect(Operation.where(resource_id: service.id).count).to eq(1)
  end
end
