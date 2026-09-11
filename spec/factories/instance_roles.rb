FactoryBot.define do
  factory :instance_role do
    user
    role { "INSTANCE_ADMIN" }

    trait :operator do
      role { "INSTANCE_OPERATOR" }
    end

    trait :auditor do
      role { "INSTANCE_AUDITOR" }
    end

    trait :revoked do
      revoked_at { Time.current }
    end

    # The grant the installation bootstrap made. At most one exists, enforced by
    # `index_instance_roles_single_bootstrap`, so a spec that needs two of these
    # is asserting something impossible.
    trait :bootstrap do
      granted_by_bootstrap { true }
      role { "INSTANCE_ADMIN" }
    end
  end
end
