FactoryBot.define do
  # An Environment links a Project to a Cluster. All three must exist for the
  # factory to construct a valid row, and the team must be the same across all
  # three (tenancy boundary). Building the association here rather than passing
  # bare IDs keeps a spec from producing a shape the application cannot produce.
  factory :environment do
    project
    cluster { association :cluster, team: project.team }
    team { project.team }

    sequence(:name) { |n| "Environment #{n}" }
    sequence(:slug) { |n| "env-#{n}" }
    type { "DEVELOPMENT" }
    status { "READY" }
    desired_revision { 1 }
    applied_revision { nil }
    auto_promote_secrets { false }

    trait :production do
      type { "PRODUCTION" }
      auto_promote_secrets { false }  # Always false for PRODUCTION (AC5)
    end

    trait :homologation do
      type { "HOMOLOGATION" }
    end

    trait :preview do
      type { "PREVIEW" }
    end

    trait :custom do
      type { "CUSTOM" }
    end

    trait :provisioning do
      status { "PROVISIONING" }
    end

    trait :degraded do
      status { "DEGRADED" }
    end

    trait :paused do
      status { "PAUSED" }
    end

    trait :deleting do
      status { "DELETING" }
    end

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
