FactoryBot.define do
  # A Project always belongs to a Team, and the Team factory already writes the
  # OWNER membership its composite foreign key requires. Building the pair here
  # rather than passing a bare `team_id` keeps a spec from producing a shape the
  # application cannot produce.
  factory :project do
    team

    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    status { "ACTIVE" }

    trait :archived do
      status { "ARCHIVED" }
    end

    # Reserved for `M02-09`; unreachable from the application in M01, and written
    # here so the guard that refuses it has something real to refuse.
    trait :deleting do
      status { "DELETING" }
    end

    trait :deleted do
      deleted_at { Time.current }
    end
  end
end
