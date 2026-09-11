FactoryBot.define do
  # DEVELOPER by default, deliberately: the interesting role is OWNER, and a
  # factory whose default is the privileged case makes a spec that forgot to say
  # what it meant look like it passed.
  factory :team_member do
    team
    user
    role { "DEVELOPER" }
    status { "ACTIVE" }
    joined_at { Time.current }

    trait :owner do
      role { "OWNER" }
    end

    trait :admin do
      role { "ADMIN" }
    end

    trait :viewer do
      role { "VIEWER" }
    end

    trait :invited do
      status { "INVITED" }
      joined_at { nil }
    end

    trait :suspended do
      status { "SUSPENDED" }
    end

    trait :removed do
      status { "REMOVED" }
    end
  end
end
