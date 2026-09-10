require "rails_helper"

# AC5: UNIQUE(scope, idempotencyKey) existe; a mesma chave no mesmo escopo produz uma operação lógica.
RSpec.describe "Operation idempotency key", :integration do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  it "returns the same operation when called with the same idempotency key at database level" do
    idempotent_key = "my-idempotent-key-#{SecureRandom.hex(8)}"

    # First operation created directly with idempotency key
    first_operation = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )

    expect(first_operation.idempotency_key).to eq(idempotent_key)

    # Second attempt with the same key should fail the unique constraint
    expect {
      Operation.create!(
        team_id: team.id,
        resource_type: "Service",
        resource_id: service.id,
        type: "UPDATE_SERVICE",
        status: Operation::PENDING,
        desired_revision: 2,
        idempotency_key: idempotent_key,
        payload: { schemaVersion: 1 }
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows different idempotency keys to create different operations" do
    key1 = "key-#{SecureRandom.hex(8)}"
    key2 = "key-#{SecureRandom.hex(8)}"

    op1 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: key1,
      payload: { schemaVersion: 1 }
    )

    op2 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 2,
      idempotency_key: key2,
      payload: { schemaVersion: 1 }
    )

    expect(op1.id).not_to eq(op2.id)
    expect(Operation.where(resource_id: service.id).count).to eq(2)
  end

  it "allows multiple operations without idempotency keys (nil is not constrained)" do
    # First operation without key
    op1 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: nil,
      payload: { schemaVersion: 1 }
    )

    # Second operation without key (nil is not unique-constrained)
    op2 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 2,
      idempotency_key: nil,
      payload: { schemaVersion: 1 }
    )

    expect(op1.idempotency_key).to be_nil
    expect(op2.idempotency_key).to be_nil
    expect(op1.id).not_to eq(op2.id)
    expect(Operation.where(resource_id: service.id).count).to eq(2)
  end

  it "enforces unique constraint at the database level across teams" do
    other_team = create(:team)
    idempotent_key = "shared-key-#{SecureRandom.hex(8)}"

    # Different teams can have the same idempotency key with the same resource
    # (constraint is per scope: team + resource + type + key)
    op1 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )

    # Same key, different team is allowed
    op2 = Operation.create!(
      team_id: other_team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )

    expect(op1.id).not_to eq(op2.id)
  end

  it "the unique constraint covers (team_id, resource_type, resource_id, type, idempotency_key)" do
    idempotent_key = "constraint-test-#{SecureRandom.hex(8)}"

    op1 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )

    # Same everything except resource_id - should succeed
    other_service = create(:service, environment: environment)
    op2 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: other_service.id,
      type: "UPDATE_SERVICE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )
    expect(op2).to be_persisted

    # Same everything except type - should succeed
    op3 = Operation.create!(
      team_id: team.id,
      resource_type: "Service",
      resource_id: service.id,
      type: "SCALE",
      status: Operation::PENDING,
      desired_revision: 1,
      idempotency_key: idempotent_key,
      payload: { schemaVersion: 1 }
    )
    expect(op3).to be_persisted

    # Identical to op1 - should fail
    expect {
      Operation.create!(
        team_id: team.id,
        resource_type: "Service",
        resource_id: service.id,
        type: "UPDATE_SERVICE",
        status: Operation::PENDING,
        desired_revision: 2,
        idempotency_key: idempotent_key,
        payload: { schemaVersion: 1 }
      )
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
