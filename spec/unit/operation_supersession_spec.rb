require "rails_helper"

RSpec.describe "Operation supersession", :unit do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  describe "#mark_superseded!" do
    it "marks an older operation as SUPERSEDED when a newer revision arrives" do
      # Create first operation for revision 5
      operation_v5 = create(:operation,
        team: team,
        resource_id: service.id,
        resource_type: "Service",
        type: "UPDATE_SERVICE",
        desired_revision: 5,
        status: Operation::QUEUED
      )

      expect(operation_v5.status).to eq(Operation::QUEUED)

      # Mark the earlier operation as superseded
      operation_v5.mark_superseded!

      expect(operation_v5.reload.status).to eq(Operation::SUPERSEDED)
    end

    it "does not change status if operation is already terminal" do
      operation = create(:operation,
        team: team,
        resource_id: service.id,
        resource_type: "Service",
        type: "UPDATE_SERVICE",
        status: Operation::SUCCEEDED,
        desired_revision: 5
      )

      # Attempting to mark as superseded when already terminal should not change it
      operation.mark_superseded!
      expect(operation.reload.status).to eq(Operation::SUCCEEDED)
    end

    it "supersedes multiple older operations when new revision arrives" do
      # Create operations for revisions 3, 4, 5
      # Note: only QUEUED and PENDING operations can be superseded; RUNNING operations
      # are already touching the runtime and cannot be marked obsolete (doc 07 §5.2).
      op_v3 = create(:operation,
        team: team,
        resource_id: service.id,
        resource_type: "Service",
        type: "UPDATE_SERVICE",
        desired_revision: 3,
        status: Operation::QUEUED
      )

      op_v4 = create(:operation,
        team: team,
        resource_id: service.id,
        resource_type: "Service",
        type: "UPDATE_SERVICE",
        desired_revision: 4,
        status: Operation::PENDING
      )

      op_v5 = create(:operation,
        team: team,
        resource_id: service.id,
        resource_type: "Service",
        type: "UPDATE_SERVICE",
        desired_revision: 5,
        status: Operation::QUEUED
      )

      # When revision 6 arrives, mark all earlier as superseded (in real life, the reconciler does this)
      [ op_v3, op_v4, op_v5 ].each(&:mark_superseded!)

      expect(op_v3.reload.status).to eq(Operation::SUPERSEDED)
      expect(op_v4.reload.status).to eq(Operation::SUPERSEDED)
      expect(op_v5.reload.status).to eq(Operation::SUPERSEDED)
    end
  end
end
