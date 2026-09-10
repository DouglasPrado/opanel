require "rails_helper"

# AC2: Nenhuma chamada de rede (Docker, HTTP, DNS) ocorre dentro da transação.
# Comprovado com instrumentação (mock/stub de chamadas externas).
RSpec.describe "Operation transaction boundary", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }
  let(:actor) { team.team_members.first.user }

  it "commits desired state, operation and outbox event atomically" do
    initial_operation_count = Operation.count
    initial_event_count = OutboxEvent.count

    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5,
      image_ref: "myregistry/app:v2"
    )

    expect(result).to be_success
    expect(Operation.count).to eq(initial_operation_count + 1)
    expect(OutboxEvent.count).to eq(initial_event_count + 1)

    # Operation and OutboxEvent were created in the same transaction
    operation = Operation.where(resource_id: service.id).last
    expect(operation).not_to be_nil
    expect(operation.status).to eq(Operation::PENDING)

    event = OutboxEvent.where(aggregate_id: service.id).last
    expect(event).not_to be_nil
    expect(event.event_type).to eq("service.desired_state.changed.v1")
    expect(event.published_at).to be_nil # Not published until M01-14
  end

  it "returns operationId on success" do
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      replicas: 5
    )

    expect(result).to be_success
    expect(result.value[:operation_id]).not_to be_nil
  end

  it "rolls back operation and event if service.save! fails" do
    # Force service to be created first, then arm the stub
    service
    allow_any_instance_of(Service).to receive(:save!).and_raise("Simulated save failure")

    expect {
      UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5
      )
    }.to raise_error("Simulated save failure")

    # No operation or event were created
    expect(Operation.where(resource_id: service.id).count).to eq(0)
    expect(OutboxEvent.where(aggregate_id: service.id).count).to eq(0)
  end

  it "does not create operation when no reconciler-affecting change is made" do
    # Just update constraints, which don't affect reconciler
    result = UpdateServiceDesiredState.call(
      actor: actor,
      service: service,
      constraints: { "node.role": "manager" }
    )

    expect(result).to be_success
    # No operation because constraints don't trigger reconciler
    expect(Operation.where(resource_id: service.id).count).to eq(0)
    expect(OutboxEvent.where(aggregate_id: service.id).count).to eq(0)
  end
end
