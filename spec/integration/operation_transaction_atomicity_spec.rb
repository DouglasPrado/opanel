require "rails_helper"

RSpec.describe "Operation transaction atomicity", :integration do
  let(:actor) { create(:user) }
  let(:team) { create(:team, owner: actor) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment, replicas: 1, team: team) }

  describe "AC1: Atomicity of desired state + Operation + OutboxEvent" do
    it "commits all three rows in one transaction" do
      expect {
        UpdateServiceDesiredState.call(
          actor: actor,
          service: service,
          expected_revision: service.desired_revision,
          replicas: 3
        )
      }.to change { Operation.count }.by(1).and change { OutboxEvent.count }.by(1)

      # All in one transaction means they all committed.
      service.reload
      expect(service.replicas).to eq(3)
      expect(service.desired_revision).to eq(2)  # incremented because replicas changed

      operation = Operation.where(resource_id: service.id).first
      expect(operation).to be_present
      expect(operation.desired_revision).to eq(2)
      expect(operation.status).to eq(Operation::PENDING)
      expect(operation.payload).to include("schemaVersion" => 1)

      outbox_event = OutboxEvent.where(aggregate_id: service.id).first
      expect(outbox_event).to be_present
      expect(outbox_event.event_type).to eq("service.desired_state.changed.v1")
      expect(outbox_event.published_at).to be_nil  # Not published yet (M01-14's job)
    end

    it "does not commit Operation if desired state update fails" do
      expect {
        UpdateServiceDesiredState.call(
          actor: actor,
          service: service,
          expected_revision: 999,  # Conflict
          replicas: 3
        )
      }.not_to change { Operation.count }
    end

    it "does not commit OutboxEvent if Operation creation fails" do
      # Simulate payload validation failure by mocking
      allow(Opanel::OperationPayload).to receive(:validate!).and_raise(ArgumentError, "Bad payload")

      expect {
        begin
          UpdateServiceDesiredState.call(
            actor: actor,
            service: service,
            expected_revision: service.desired_revision,
            replicas: 3
          )
        rescue ArgumentError
          # Expected
        end
      }.not_to change { OutboxEvent.count }
    end
  end

  describe "AC12: Crash between COMMIT and publish" do
    it "preserves intent after simulated process crash" do
      # Update the service, which commits Operation + OutboxEvent
      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        expected_revision: service.desired_revision,
        replicas: 5
      )

      expect(result.success?).to be true

      # Simulate the process crashing after commit but before publish
      # by fetching a new connection and verifying all rows exist
      new_connection = ActiveRecord::Base.connection_pool.checkout

      begin
        # Verify the Service desired state survived
        service_check = new_connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT replicas, desired_revision FROM services WHERE id = ?",
            service.id
          ])
        ).first
        expect(service_check["replicas"]).to eq(5)
        expect(service_check["desired_revision"]).to eq(2)

        # Verify the Operation survived in PENDING state
        operation_check = new_connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT status, desired_revision, payload FROM operations WHERE resource_id = ?",
            service.id
          ])
        ).first
        expect(operation_check).to be_present
        expect(operation_check["status"]).to eq(Operation::PENDING)
        expect(operation_check["desired_revision"]).to eq(2)

        # Verify the OutboxEvent survived with published_at = NULL
        outbox_check = new_connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT event_type, published_at FROM outbox_events WHERE aggregate_id = ?",
            service.id
          ])
        ).first
        expect(outbox_check).to be_present
        expect(outbox_check["event_type"]).to eq("service.desired_state.changed.v1")
        expect(outbox_check["published_at"]).to be_nil

        # Verify mutual consistency: Operation payload references the revision
        payload = JSON.parse(operation_check["payload"])
        expect(payload["desired_revision"]).to eq(2)
        expect(payload["replicas"]).to eq(5)
      ensure
        ActiveRecord::Base.connection_pool.checkin(new_connection)
      end
    end
  end

  describe "AC2: No network calls inside transaction" do
    it "does not make HTTP calls during UpdateServiceDesiredState" do
      # Block HTTP calls to verify none are made (instrument instance method)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise("HTTP call should not happen in transaction")

      # Verify SwarmExecutor is not called
      expect(SwarmExecutor).not_to receive(:new)

      expect {
        UpdateServiceDesiredState.call(
          actor: actor,
          service: service,
          expected_revision: service.desired_revision,
          replicas: 3
        )
      }.not_to raise_error

      # Verify the update succeeded
      expect(service.reload.replicas).to eq(3)
    end
  end
end
