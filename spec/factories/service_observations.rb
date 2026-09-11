FactoryBot.define do
  factory :service_observation do
    service
    swarm_service_id { "svc_#{SecureRandom.hex(8)}" }
    desired_tasks { 1 }
    running_tasks { 1 }
    healthy_tasks { 1 }
    failed_tasks { 0 }
    observed_image_digest { "myapp@sha256:#{SecureRandom.hex(32)}" }
    update_status { "completed" }
    nodes { [ "node1" ] }
    docker_version_index { rand(1..1000) }
    observed_at { Time.current }
  end
end
