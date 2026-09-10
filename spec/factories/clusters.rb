FactoryBot.define do
  # A Cluster always belongs to a Team — `team_id` is NOT NULL by SC-12 — and the
  # Team factory writes the OWNER membership its composite foreign key needs.
  factory :cluster do
    team

    sequence(:name) { |n| "Cluster #{n}" }
    sequence(:slug) { |n| "cluster-#{n}" }
    status { "PROVISIONING" }

    # A Swarm id of the shape the Engine produces, so the CHECK and the partial
    # unique index are both exercised by ordinary fixtures rather than only by the
    # examples that go looking for them.
    trait :bootstrapped do
      sequence(:swarm_id) { |n| "swarm#{n.to_s.rjust(19, '0')}" }
      advertise_address { "10.0.0.1" }
      status { "READY" }
      observed_at { Time.current }
    end

    trait :stale do
      status { "READY" }
      observed_at { (Cluster::FRESH_OBSERVATION_SECONDS + 60).seconds.ago }
    end

    trait :unreachable do
      status { "UNREACHABLE" }
      unreachable_reason { "DAEMON_UNREACHABLE" }
      observed_at { Time.current }
    end
  end
end
