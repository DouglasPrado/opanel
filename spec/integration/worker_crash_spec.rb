require "rails_helper"

# The contract this Story has to make true, in the transport that will actually
# carry the work: if a worker dies mid-execution, the intent is not lost and the
# effect is not applied twice.
#
# Solid Queue does not silently re-run a crashed job. When the dead process is
# pruned, its claimed execution is marked failed and it stays there — which is the
# concrete reason durability cannot live in the broker. Re-running it is a
# deliberate recovery action, the same one the Operation sweep of M01-15 will
# perform from PostgreSQL.
RSpec.describe "a worker that dies mid-execution", :solid_queue_worker, type: :integration do
  # Real processes cannot see data held open in this process's transaction.
  self.use_transactional_tests = false

  let(:checkpoint_name) { "crash-recovery-#{SecureRandom.hex(4)}" }

  before do
    SolidQueue::Job.destroy_all
    SolidQueue::Process.delete_all
  end

  after do
    InfrastructureCheckpoint.where(name: checkpoint_name).delete_all
    SolidQueue::Job.destroy_all
    SolidQueue::Process.delete_all
  end

  it "does not duplicate the idempotent effect when the job runs again" do
    worker = start_worker
    ExampleCheckpointJob.perform_later(name: checkpoint_name, hold_seconds: 6)

    wait_until("the job to be claimed by the worker") { SolidQueue::ClaimedExecution.exists? }

    # SIGKILL the whole process group while `perform` is still inside its hold.
    kill_worker(worker)

    expect(InfrastructureCheckpoint.where(name: checkpoint_name).count)
      .to eq(0), "the job was killed before it applied its effect"

    # A new supervisor prunes the dead process and fails what it had claimed.
    start_worker
    failed = wait_until("the orphaned execution to be failed") { SolidQueue::FailedExecution.first }

    expect(failed.exception_class).to match(/ProcessPrunedError|ProcessMissingError/),
      "the failure must name the crash, not some unrelated error"

    # The recovery action: re-run what the crash left behind.
    failed.retry

    wait_until("the job to finish on the new worker") do
      InfrastructureCheckpoint.find_by(name: checkpoint_name)
    end

    # Give the worker room to finish anything it might still be doing before the
    # counts are read, so a passing assertion is not just an early read.
    sleep 1

    checkpoints = InfrastructureCheckpoint.where(name: checkpoint_name)

    expect(checkpoints.count).to eq(1),
      "the effect was duplicated: the job is not idempotent across a crash"
    expect(checkpoints.first.counter).to be >= 1,
      "the execution witness did not record the recovered run"
  end

  it "keeps a killed job's intent recoverable rather than silently dropping it" do
    worker = start_worker
    ExampleCheckpointJob.perform_later(name: checkpoint_name, hold_seconds: 6)

    wait_until("the job to be claimed") { SolidQueue::ClaimedExecution.exists? }
    kill_worker(worker)

    start_worker
    wait_until("the execution to become recoverable") { SolidQueue::FailedExecution.exists? }

    # The job row survives the crash: nothing about the request disappeared with
    # the process. This is the property M01-15 builds the Operation sweep on.
    expect(SolidQueue::Job.count).to eq(1)
  end
end
