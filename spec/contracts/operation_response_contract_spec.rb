require "rails_helper"

# AC3: Mutação assíncrona retorna operationId e não aguarda o runtime.
# Contract test: a resposta HTTP de um POST que altera desired state deve retornar operationId.
RSpec.describe "Operation response contract", :integration do
  describe "async mutation returns operationId" do
    it "UpdateServiceDesiredState command returns operation_id in result" do
      team = create(:team)
      project = create(:project, team: team)
      environment = create(:environment, project: project)
      service = create(:service, environment: environment)
      actor = team.team_members.first.user

      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5,
        image_ref: "myregistry/app:v2"
      )

      expect(result).to be_success
      expect(result.value[:operation_id]).not_to be_nil

      # Verify the operation exists and is in PENDING state
      operation_id = Opanel::Identifier.parse(:operation, result.value[:operation_id])
      operation = OperationById.call(actor: actor, operation_id: operation_id).value[:operation]
      expect(operation.status).to eq(Operation::PENDING)
      expect(operation.desired_revision).to be > 0
    end

    it "does not wait for runtime before returning" do
      team = create(:team)
      project = create(:project, team: team)
      environment = create(:environment, project: project)
      service = create(:service, environment: environment)
      actor = team.team_members.first.user

      start_time = Time.current
      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5
      )
      elapsed = (Time.current - start_time).to_f

      expect(result).to be_success
      # Command should return in < 100ms (very fast, no external calls)
      expect(elapsed).to be < 0.5
    end

    it "returns error with stable code when validation fails" do
      team = create(:team)
      project = create(:project, team: team)
      environment = create(:environment, project: project)
      service = create(:service, environment: environment)
      actor = team.team_members.first.user

      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: -1 # Invalid
      )

      expect(result).not_to be_success
      expect(result.code).not_to be_nil
      # Code is stable, not a stack trace
      expect(result.code).to match(/^[A-Z_]+$/)
      expect(result.code).not_to include("::")
      expect(result.code).not_to include("Error")
    end
  end

  describe "operation payload structure (AC3 detail)" do
    it "operation payload contains schemaVersion and required fields" do
      team = create(:team)
      project = create(:project, team: team)
      environment = create(:environment, project: project)
      service = create(:service, environment: environment)
      actor = team.team_members.first.user

      UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5
      )

      operation = Operation.where(resource_id: service.id).last
      expect(operation.payload).to have_key("schemaVersion")
      expect(operation.payload["schemaVersion"]).to eq(1)
      expect(operation.payload).to have_key("service_id")
      expect(operation.payload).to have_key("desired_revision")
    end
  end
end
