# frozen_string_literal: true

require "rails_helper"


RSpec.describe "Queue backpressure (AC7)" do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  context "backpressure applies to all operation creation" do
    let(:actor) { team.team_members.first.user }

    it "defers Operation creation when queue backlog exceeds high-water mark" do
      # Override the high-water mark to a low value for testing
      allow(Opanel::Configuration).to receive(:queue_backpressure_high_water_mark).and_return(5)

      # Fill the outbox beyond the high-water mark
      10.times do
        create(:outbox_event, aggregate_id: service.id, published_at: nil)
      end

      # Now attempt to create a new operation
      # The command should still succeed (nothing is rejected), but next_attempt_at
      # should be deferred by the configured backpressure delay
      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 5,
        image_ref: nil,
        ports: nil,
        health_check: nil,
        cpu_reservation: nil,
        cpu_limit: nil,
        memory_reservation: nil,
        memory_limit: nil,
        constraints: nil,
        expected_revision: nil
      )

      expect(result).to be_success

      # Operation should be deferred
      operation = Operation.where(resource_id: service.id).last
      expect(operation).to be_present
      expect(operation.next_attempt_at).to be > Time.current.utc
    end

    it "does not lose operations, only defers them" do
      # Fill the outbox
      10.times do
        create(:outbox_event, aggregate_id: service.id, published_at: nil)
      end

      # Create an operation under backpressure
      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 3,
        image_ref: nil,
        ports: nil,
        health_check: nil,
        cpu_reservation: nil,
        cpu_limit: nil,
        memory_reservation: nil,
        memory_limit: nil,
        constraints: nil,
        expected_revision: nil
      )

      expect(result).to be_success

      # Verify the operation was persisted
      operation = Operation.where(resource_id: service.id).last
      expect(operation).to be_present
      expect(operation.status).to eq(Operation::PENDING)
      expect(operation.next_attempt_at).not_to be_nil
    end

    it "does not apply backpressure when queue is healthy" do
      # No unpublished events, queue is empty
      result = UpdateServiceDesiredState.call(
        actor: actor,
        service: service,
        replicas: 2,
        image_ref: nil,
        ports: nil,
        health_check: nil,
        cpu_reservation: nil,
        cpu_limit: nil,
        memory_reservation: nil,
        memory_limit: nil,
        constraints: nil,
        expected_revision: nil
      )

      expect(result).to be_success

      operation = Operation.where(resource_id: service.id).last

      # Operation should have normal timing, not deferred
      # (next_attempt_at should be soon or now, not far in the future)
      expect(operation.next_attempt_at).to be <= Time.current.utc + 10.seconds
    end
  end
end
