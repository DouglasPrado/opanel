FactoryBot.define do
  # A Service links an Environment to an OCI image. The environment, team, and
  # image must all be valid for the factory to construct a valid row.
  factory :service do
    environment
    team { environment.team }

    sequence(:name) { |n| "Service #{n}" }
    sequence(:slug) { |n| "svc-#{n}" }
    service_type { "WEB" }
    image_ref { "docker.io/nginx:latest" }
    replicas { 1 }
    ports { {} }
    health_check { nil }
    cpu_reservation { nil }
    cpu_limit { nil }
    memory_reservation { nil }
    memory_limit { nil }
    constraints { nil }

    # Technical name derived from IDs. The factory builds it deterministically
    # but does not check uniqueness — the model and database do.
    technical_name {
      "#{environment.project.team.slug}-#{environment.project.slug}-#{environment.slug}-#{slug}"
    }

    status { "DRAFT" }
    desired_revision { 1 }
    applied_revision { nil }

    trait :web do
      service_type { "WEB" }
    end

    trait :worker do
      service_type { "WORKER" }
    end

    trait :cron do
      service_type { "CRON" }
    end

    trait :task do
      service_type { "TASK" }
    end

    trait :database do
      service_type { "DATABASE" }
    end

    trait :cache do
      service_type { "CACHE" }
    end

    trait :draft do
      status { "DRAFT" }
    end

    trait :provisioning do
      status { "PROVISIONING" }
    end

    trait :running do
      status { "RUNNING" }
    end

    trait :degraded do
      status { "DEGRADED" }
    end

    trait :stopped do
      status { "STOPPED" }
    end

    trait :deleting do
      status { "DELETING" }
    end

    trait :deleted do
      deleted_at { Time.current }
    end

    trait :archived do
      archived_at { Time.current }
    end

    trait :with_resource_limits do
      cpu_reservation { 100 }
      cpu_limit { 200 }
      memory_reservation { 256 }
      memory_limit { 512 }
    end

    trait :with_custom_image do
      image_ref { "gcr.io/my-project/my-service:v1.0.0" }
    end

    trait :with_digest do
      image_ref { "docker.io/nginx@sha256:abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234" }
    end
  end
end
