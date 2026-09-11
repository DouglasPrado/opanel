require "rails_helper"

RSpec.describe Operation, ".state_machine_and_validations" do
  describe "state machine" do
    let(:operation) { build(:operation, status: Operation::PENDING) }

    describe "#can_transition_to?" do
      it "allows valid transitions from PENDING" do
        expect(operation.can_transition_to?(Operation::QUEUED)).to be true
        expect(operation.can_transition_to?(Operation::CANCELED)).to be true
      end

      it "rejects invalid transitions from PENDING" do
        expect(operation.can_transition_to?(Operation::RUNNING)).to be false
        expect(operation.can_transition_to?(Operation::SUCCEEDED)).to be false
      end

      it "allows QUEUED → RUNNING" do
        operation.status = Operation::QUEUED
        expect(operation.can_transition_to?(Operation::RUNNING)).to be true
      end

      it "allows RUNNING → WAITING_RUNTIME, SUCCEEDED, RETRYABLE, FAILED" do
        operation.status = Operation::RUNNING
        expect(operation.can_transition_to?(Operation::WAITING_RUNTIME)).to be true
        expect(operation.can_transition_to?(Operation::SUCCEEDED)).to be true
        expect(operation.can_transition_to?(Operation::RETRYABLE)).to be true
        expect(operation.can_transition_to?(Operation::FAILED)).to be true
      end

      it "allows VERIFYING → SUCCEEDED, RETRYABLE, FAILED" do
        operation.status = Operation::VERIFYING
        expect(operation.can_transition_to?(Operation::SUCCEEDED)).to be true
        expect(operation.can_transition_to?(Operation::RETRYABLE)).to be true
        expect(operation.can_transition_to?(Operation::FAILED)).to be true
      end

      it "rejects transitions from terminal states" do
        terminal_statuses = [
          Operation::SUCCEEDED, Operation::FAILED, Operation::CANCELED,
          Operation::SUPERSEDED, Operation::TIMED_OUT
        ]
        terminal_statuses.each do |status|
          operation.status = status
          expect(operation.can_transition_to?(Operation::RUNNING)).to be false
        end
      end

      it "rejects self-transitions" do
        expect(operation.can_transition_to?(Operation::PENDING)).to be false
      end
    end

    describe "#transition_to!" do
      let(:operation) { create(:operation, status: Operation::PENDING) }

      it "updates status when transition is valid" do
        operation.transition_to!(Operation::QUEUED)
        expect(operation.reload.status).to eq(Operation::QUEUED)
      end

      it "raises when transition is invalid" do
        expect { operation.transition_to!(Operation::RUNNING) }.to raise_error(/Invalid transition/)
      end
    end

    describe "terminal?" do
      it "returns true for terminal statuses" do
        [
          Operation::SUCCEEDED, Operation::FAILED, Operation::CANCELED,
          Operation::SUPERSEDED, Operation::TIMED_OUT
        ].each do |status|
          operation.status = status
          expect(operation.terminal?).to be true
        end
      end

      it "returns false for non-terminal statuses" do
        [
          Operation::PENDING, Operation::QUEUED, Operation::RUNNING,
          Operation::WAITING_RUNTIME, Operation::VERIFYING
        ].each do |status|
          operation.status = status
          expect(operation.terminal?).to be false
        end
      end
    end

    describe "#mark_superseded!" do
      let(:operation) { create(:operation, status: Operation::PENDING) }

      it "transitions to SUPERSEDED if not already terminal" do
        operation.mark_superseded!
        expect(operation.reload.status).to eq(Operation::SUPERSEDED)
      end

      it "does not change status if already terminal" do
        terminal_op = create(:operation, status: Operation::SUCCEEDED)
        expect { terminal_op.mark_superseded! }.not_to change { terminal_op.reload.status }
      end
    end
  end

  describe "validations" do
    # For validations tests, we use create to ensure the team is persisted,
    # since build creates the association but doesn't persist it, and validations
    # check the foreign key constraint.
    let(:operation) { create(:operation) }

    it "requires team_id" do
      op = build(:operation, team_id: nil)
      expect(op).not_to be_valid
      expect(op.errors[:team_id]).to be_present
    end

    it "requires resource_type" do
      op = build(:operation, resource_type: nil)
      expect(op).not_to be_valid
      expect(op.errors[:resource_type]).to be_present
    end

    it "requires resource_id" do
      op = build(:operation, resource_id: nil)
      expect(op).not_to be_valid
      expect(op.errors[:resource_id]).to be_present
    end

    it "requires type" do
      op = build(:operation, type: nil)
      expect(op).not_to be_valid
      expect(op.errors[:type]).to be_present
    end

    it "requires status to be one of STATUSES" do
      op = build(:operation, status: "INVALID")
      expect(op).not_to be_valid
      expect(op.errors[:status]).to be_present
    end

    it "requires desired_revision to be present" do
      op = build(:operation, desired_revision: nil)
      expect(op).not_to be_valid
      expect(op.errors[:desired_revision]).to be_present
    end

    it "requires payload to be present" do
      op = build(:operation, payload: nil)
      expect(op).not_to be_valid
      expect(op.errors[:payload]).to be_present
    end

    it "allows error_code to be nil" do
      expect(operation.error_code).to be_nil
      expect(operation).to be_valid
    end

    it "requires error_code to be one of ERROR_CLASSES if present" do
      op = build(:operation, error_code: "invalid_error")
      expect(op).not_to be_valid
      expect(op.errors[:error_code]).to be_present
    end

    it "accepts valid error codes" do
      team = create(:team)
      Operation::ERROR_CLASSES.each do |error_class|
        op = build(:operation, team: team, error_code: error_class.to_s)
        expect(op).to be_valid
      end
    end
  end

  describe "STI disabled" do
    it "creates an Operation with type=SCALE and reloads it correctly" do
      op = create(:operation, type: "SCALE")
      reloaded = Operation.find(op.id)
      expect(reloaded.type).to eq("SCALE")
      expect(reloaded.class.name).to eq("Operation")
    end
  end
end
