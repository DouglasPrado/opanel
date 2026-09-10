FactoryBot.define do
  factory :operation do
    team { association :team }
    sequence(:id) { |n| "op_#{n.to_s.rjust(24, '0')}" }

    resource_type { "Service" }
    sequence(:resource_id) { |n| "svc_#{n.to_s.rjust(21, '0')}" }

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
    sequence(:id) { |n| "evt_#{n.to_s.rjust(21, '0')}" }

    aggregate_type { "Service" }
    sequence(:aggregate_id) { |n| "svc_#{n.to_s.rjust(21, '0')}" }

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
end
