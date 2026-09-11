require "rails_helper"

RSpec.describe "Service observation never contains secrets" do
  let(:environment) { create(:environment) }
  let(:service) do
    create(:service,
      environment: environment,
      swarm_service_id: "abcdef0123456789abcdef0123"
    )
  end

  # Fake executor that returns a service observation
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
        replicas: 2
      ),
      ids: [ "runtime1" ]
    )
  end

  let(:tasks_result) do
    SwarmObservations.tasks(count: 2)
  end

  describe "observation excludes environment variables" do
    it "does not store env variables in observation" do
      result = ObserveService.call(service: service, executor: fake_executor)

      observation = result.value

      # ServiceObservation should not have a column for env vars
      expect { observation.environment_variables }.to raise_error(NoMethodError)
    end
  end

  describe "observation excludes secret values" do
    it "does not store secret values in observation" do
      result = ObserveService.call(service: service, executor: fake_executor)

      observation = result.value

      # ServiceObservation should not have a column for secrets
      expect { observation.secrets }.to raise_error(NoMethodError)
    end
  end

  describe "observation payload is sanitized when serialized" do
    it "does not include environment or secrets in JSON representation" do
      result = ObserveService.call(service: service, executor: fake_executor)

      observation = result.value
      json_data = observation.as_json

      # The observation JSON should only contain the allowed fields
      expect(json_data).to include(
        "desired_tasks",
        "running_tasks",
        "healthy_tasks",
        "failed_tasks",
        "observed_image_digest"
      )

      # Should NOT include these
      expect(json_data).not_to include("env", "environment_variables")
      expect(json_data).not_to include("secrets", "secret_values")
    end
  end

  describe "observation columns are strictly defined" do
    it "observation model has no secrets-related columns" do
      observation = build(:service_observation)

      # These columns should not exist on ServiceObservation
      expect(observation.attributes.keys).not_to include(
        "environment_variables",
        "secrets",
        "secret_values",
        "secret_bindings"
      )
    end
  end

  describe "AC9 compliance: no env or secret content in observation" do
    it "satisfies AC9 by design: observation schema excludes sensitive fields" do
      # AC9: A observação não registra variável de ambiente nem conteúdo de secret

      result = ObserveService.call(service: service, executor: fake_executor)
      expect(result).to be_success

      observation = result.value

      # Verify the observation can never contain env or secret content
      # because the schema doesn't have those columns
      cols = ServiceObservation.column_names

      expect(cols).not_to include("environment_variables")
      expect(cols).not_to include("env_vars")
      expect(cols).not_to include("secrets")
      expect(cols).not_to include("secret_values")

      # Only allowed columns for observation
      expect(cols).to include(
        "id",
        "service_id",
        "desired_tasks",
        "running_tasks",
        "healthy_tasks",
        "failed_tasks",
        "observed_image_digest",
        "docker_version_index",
        "observed_at"
      )
    end
  end
end
