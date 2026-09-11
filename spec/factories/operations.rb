FactoryBot.define do
  factory :operation do
    team { association :team }
    id { Opanel::Identifier.generate }

    resource_type { "Service" }
    resource_id { Opanel::Identifier.generate }

    type { "UPDATE_SERVICE" }
    status { Operation::PENDING }
    desired_revision { 1 }

    idempotency_key { nil }
    lease_owner { nil }
    lease_until { nil }
    fencing_token { nil }

    attempt_count { 0 }

    payload do
      {
        schemaVersion: 1,
        service_id: "svc_test",
        desired_revision: 1,
        replicas: 3,
        image_ref: "myregistry/app:latest",
        image_digest: nil,
        ports: {},
        health_check: nil,
        cpu_reservation: nil,
        cpu_limit: nil,
        memory_reservation: nil,
        memory_limit: nil,
        constraints: nil,
        correlation_id: SecureRandom.uuid,
        request_id: SecureRandom.uuid,
        actor_id: "usr_test"
      }
    end

    error_code { nil }
    request_id { SecureRandom.uuid }
    correlation_id { SecureRandom.uuid }
    requested_by { "usr_test" }

    # Traits for different operation statuses (M01-14 testing).
    trait :queued do
      status { Operation::QUEUED }
      next_attempt_at { Time.current.utc }
    end

    trait :running do
      status { Operation::RUNNING }
      started_at { 1.minute.ago }
      next_attempt_at { Time.current.utc }
    end

    trait :succeeded do
      status { Operation::SUCCEEDED }
      started_at { 5.minutes.ago }
      finished_at { 1.minute.ago }
    end

    trait :failed do
      status { Operation::FAILED }
      started_at { 5.minutes.ago }
      finished_at { 1.minute.ago }
      error_code { "transient" }
    end

    trait :superseded do
      status { Operation::SUPERSEDED }
      finished_at { 1.minute.ago }
    end
  end

  factory :operation_attempt do
    operation { association :operation }
    sequence(:attempt_number, 1)

    executor_id { "executor-1" }
    started_at { Time.current.utc }
    finished_at { nil }

    outcome { "NOOP" }
    error_code { nil }
    error_message { nil }

    metadata { {} }
  end

  factory :outbox_event do
    id { Opanel::Identifier.generate }

    aggregate_type { "Service" }
    aggregate_id { Opanel::Identifier.generate }

    event_type { "service.desired_state.changed.v1" }
    schema_version { 1 }

    payload do
      {
        service_id: "svc_test",
        desired_revision: 1,
        operation_id: "op_test"
      }
    end

    partition_key { "service_1" }
    occurred_at { Time.current.utc }
    published_at { nil }
  end

  factory :inbox_event do
    id { Opanel::Identifier.generate }

    source { "test_source" }
    sequence(:source_event_id) { |n| "ext_#{n}" }

    processed_at { nil }
    result_ref { nil }
  end

  factory :resource_lock do
    team { association :team }
    id { Opanel::Identifier.generate }

    sequence(:scope_key) { |n| "resource-lock-#{n}" }
    owner { "test-worker-#{Kernel.rand(1000)}" }
    lease_until { Time.current + 120.seconds }
    fencing_token { 0 }
  end
end
