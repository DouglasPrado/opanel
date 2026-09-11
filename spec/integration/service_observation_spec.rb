require "rails_helper"

RSpec.describe "Service observation persistence and staleness", :integration do
  let(:environment) { create(:environment) }
  let(:service) do
    create(:service, environment: environment, swarm_service_id: "abcdef0123456789abcdef0123")
  end

  # Create a fake executor with scripted responses
  let(:fake_executor) do
    FakeSwarmExecutor.new(
      "inspect_service" => [ observation_result ],
      "list_tasks" => [ tasks_result ]
    )
  end

  let(:observation_result) do
    SwarmObservations.applied(
      SwarmObservations.service_observation(
        service,
        image: "myapp:latest@sha256:abc123",
        replicas: 3,
        version: 100
      ),
      ids: [ "runtime1" ]
    )
  end

  let(:tasks_result) do
    SwarmObservations.tasks(count: 3)
  end

  describe "observation persistence" do
    it "creates a ServiceObservation record" do
      result = ObserveService.call(service: service, executor: fake_executor)

      expect(result).to be_success
      expect(service.service_observations.count).to eq(1)
    end

    it "stores observed timestamp" do
      before_time = Time.current
      result = ObserveService.call(service: service, executor: fake_executor)
      after_time = Time.current

      observation = result.value
      expect(observation.observed_at).to be_between(before_time, after_time)
    end
  end

  describe "out-of-order observation handling" do
    it "accepts observation with no prior observations" do
      result = ObserveService.call(service: service, executor: fake_executor)
      expect(result).to be_success
    end

    it "rejects observation with lower docker_version_index" do
      # Create first observation with higher version
      create(:service_observation,
        service: service,
        docker_version_index: 100
      )

      # Create executor that returns lower version
      old_version_executor = FakeSwarmExecutor.new(
        "inspect_service" => [ SwarmObservations.applied(
          SwarmObservations.service_observation(
            service,
            image: "myapp:latest@sha256:abc123",
            version: 50
          )
        ) ],
        "list_tasks" => [ SwarmObservations.tasks(count: 3) ]
      )

      result = ObserveService.call(service: service, executor: old_version_executor)

      expect(result).to be_failure
      expect(result.code).to eq("observation_out_of_order")
    end

    it "accepts observation with higher docker_version_index" do
      # Create first observation
      create(:service_observation,
        service: service,
        docker_version_index: 50
      )

      # Create executor that returns higher version
      new_version_executor = FakeSwarmExecutor.new(
        "inspect_service" => [ SwarmObservations.applied(
          SwarmObservations.service_observation(
            service,
            image: "myapp:latest@sha256:abc123",
            version: 100
          )
        ) ],
        "list_tasks" => [ SwarmObservations.tasks(count: 3) ]
      )

      result = ObserveService.call(service: service, executor: new_version_executor)

      expect(result).to be_success
      expect(service.service_observations.count).to eq(2)
    end
  end

  describe "failure handling" do
    it "returns failure when service has no swarm_service_id" do
      service_without_swarm_id = create(:service, environment: environment, swarm_service_id: nil)

      result = ObserveService.call(service: service_without_swarm_id, executor: fake_executor)

      expect(result).to be_failure
      expect(result.code).to eq("service_not_yet_provisioned")
    end

    it "returns failure when executor is unavailable" do
      failed_executor = FakeSwarmExecutor.new(
        "inspect_service" => [ SwarmObservations.not_found ],
        "list_tasks" => [ SwarmObservations.tasks(count: 0) ]
      )

      result = ObserveService.call(service: service, executor: failed_executor)

      expect(result).to be_failure
      expect(result.code).to eq("observation_failed")
    end

    it "preserves previous observation when observation fails" do
      # Create initial observation
      initial_obs = create(:service_observation,
        service: service,
        observed_at: 10.minutes.ago,
        running_tasks: 3
      )

      # Failed executor
      failed_executor = FakeSwarmExecutor.new(
        "inspect_service" => [ SwarmObservations.not_found ],
        "list_tasks" => [ SwarmObservations.tasks(count: 0) ]
      )

      result = ObserveService.call(service: service, executor: failed_executor)

      # Observation count should not increase
      expect(service.service_observations.count).to eq(1)

      # The old observation should still exist with its original timestamp
      reloaded = service.service_observations.first
      expect(reloaded.observed_at).to be_within(1.second).of(initial_obs.observed_at)
    end
  end

  describe "observation and service relationship" do
    it "deletes observations when service is deleted" do
      result = ObserveService.call(service: service, executor: fake_executor)
      observation_id = result.value.id

      expect(ServiceObservation.where(id: observation_id)).to exist

      service.destroy

      expect(ServiceObservation.where(id: observation_id)).not_to exist
    end
  end
end
