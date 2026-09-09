FactoryBot.define do
  # A Team is never valid on its own: the composite foreign key requires the
  # membership its `owner_user_id` points at (doc 04 §3.2). The factory therefore
  # writes the pair, exactly as `CreateTeam` does — a factory that produced a
  # Team without its OWNER would build a shape the application cannot produce,
  # and the only reason it would appear to work in a spec is that the deferred
  # constraint is never reached inside a rolled-back transaction.
  factory :team do
    transient do
      owner { association(:user) }
    end

    sequence(:name) { |n| "Team #{n}" }
    sequence(:slug) { |n| "team-#{n}" }
    status { "ACTIVE" }

    owner_user_id { owner.id }

    after(:create) do |team, evaluator|
      create(:team_member, team: team, user: evaluator.owner, role: "OWNER", status: "ACTIVE")
    end

    # The Team whose OWNER was suspended by a security procedure. Both rows move
    # together because neither is accepted alone.
    trait :ownership_recovery_required do
      status { "OWNERSHIP_RECOVERY_REQUIRED" }

      after(:create) do |team, evaluator|
        team.team_members.find_by(user_id: evaluator.owner.id).update_columns(status: "SUSPENDED")
      end
    end
  end
end
