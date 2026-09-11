FactoryBot.define do
  factory :network do
    environment
    cluster { environment.cluster }
    team { environment.team }

    # The name is deterministic from the Environment's technical_name.
    # This can't be set via a sequence; it will be set by the test or by the Command.
    name { "net_generated_#{SecureRandom.hex(4)}" }
    driver { "overlay" }
    encrypted { false }
    status { "PROVISIONING" }
    desired_revision { 1 }
    applied_revision { nil }

    trait :ready do
      status { "READY" }
      applied_revision { desired_revision }
      swarm_network_id { "net_#{SecureRandom.hex(12)}" }
    end

    trait :degraded do
      status { "DEGRADED" }
    end
  end
end
