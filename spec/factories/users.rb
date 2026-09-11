FactoryBot.define do
  # Minimal on purpose (Annex D §22). The identifier is never set here: it comes
  # from `UlidPrimaryKey`, so a factory cannot quietly produce a shape the
  # application never produces (ADR-0002).
  #
  # The password is a **transient**. No row this factory writes carries a
  # credential — only the Argon2id digest of one — and the plaintext exists for
  # the duration of the example that asked for it.
  factory :user do
    sequence(:email) { |n| "person-#{n}@example.test" }
    display_name { "Test Person" }
    status { "ACTIVE" }

    transient do
      # Obviously fake, low entropy, and allowlisted in
      # config/security/gitleaks.toml so the secret scan does not report the
      # fixture it is meant to ignore.
      password { "hunter2-hunter2-hunter2" }
    end

    password_digest { Opanel::PasswordHashing.create(password) }

    trait :suspended do
      status { "SUSPENDED" }
    end

    trait :deleted_pending do
      status { "DELETED_PENDING" }
    end
  end
end
