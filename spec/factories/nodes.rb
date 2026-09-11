FactoryBot.define do
  # A Node always belongs to a Cluster.
  factory :node do
    cluster

    sequence(:swarm_node_id) { |n| "swarmnode#{n.to_s.rjust(20, '0')}" }
    sequence(:hostname) { |n| "node-#{n}" }
    role { "MANAGER" }
    availability { "ACTIVE" }
    status { "JOINING" }
    advertise_address { "10.0.0.#{rand(1..254)}" }

    trait :manager do
      role { "MANAGER" }
    end

    trait :worker do
      role { "WORKER" }
    end

    trait :ready do
      status { "READY" }
      last_seen_at { Time.current }
    end

    trait :degraded do
      status { "DEGRADED" }
      last_seen_at { Time.current }
    end

    trait :down do
      status { "DOWN" }
      last_seen_at { Time.current }
    end

    trait :stale do
      last_seen_at { (Node::FRESH_OBSERVATION_SECONDS + 60).seconds.ago }
    end

    trait :fresh do
      last_seen_at { Time.current }
    end

    trait :with_observation do
      after :create do |node|
        create(:node_observation, node: node, status: node.status,
          availability: node.availability, observed_at: node.last_seen_at || Time.current)
      end
    end
  end

  factory :node_observation do
    node

    status { "READY" }
    availability { "ACTIVE" }
    observed_at { Time.current }
    engine_version { "27.0.0" }
  end
end
