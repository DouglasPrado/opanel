require "rails_helper"
require "yaml"
require "erb"

RSpec.describe "queue configuration", type: :integration do
  let(:queue_yml) do
    YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
  end

  let(:configured_queues) do
    queue_yml.fetch("default").fetch("workers").flat_map { |worker| Array(worker.fetch("queues")) }
  end

  it "names exactly the six logical queues of doc 07 §9.1" do
    expect(Opanel::Queues::ALL).to eq(%w[deployments runtime cluster certificates backup-dr system])
  end

  it "gives every logical queue a worker" do
    expect(configured_queues.sort).to eq(Opanel::Queues::ALL.sort),
      "config/queue.yml and Opanel::Queues::ALL disagree: #{configured_queues.inspect}"
  end

  it "assigns each queue to exactly one worker group" do
    duplicated = configured_queues.tally.select { |_queue, count| count > 1 }

    expect(duplicated).to be_empty, "a queue served by two worker groups doubles its concurrency: #{duplicated.inspect}"
  end

  it "does not fall back to a catch-all worker" do
    expect(configured_queues).not_to include("*"),
      "a `*` worker erases the per-queue concurrency profile doc 07 §9.1 asks for"
  end

  it "configures every environment the application runs in" do
    expect(queue_yml.keys).to include("development", "test", "ci", "production")
  end

  it "runs Solid Queue in every environment, not an in-process adapter" do
    expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::SolidQueueAdapter)
  end

  it "ships a worker entry point separate from the web server" do
    jobs = Rails.root.join("bin/jobs")

    expect(jobs).to be_file
    expect(jobs).to be_executable
    expect(jobs.read).to include("SolidQueue::Cli")
  end

  it "places the example jobs on a declared queue" do
    [ ExampleCheckpointJob, ExampleTransientFailureJob ].each do |job_class|
      expect(Opanel::Queues::ALL).to include(job_class.new.queue_name)
    end
  end
end
