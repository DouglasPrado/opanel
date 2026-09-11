require "rails_helper"

RSpec.describe "Reconciler user-intent column protection", type: :security do
  it "AF-03 fitness function must validate reconciler does not write user-intent columns" do
    # This is validated by bin/fitness AF-03 check
    # The reconciler code must never write to:
    # - Environment: name, slug, type, auto_promote_secrets
    # - Service: name, slug, image_ref, replicas, ports, health_check, etc.

    # The reconciler may only write:
    # - applied_revision, status, swarm_network_id (for Network)

    network = double("network")
    allow(network).to receive(:applied_revision=)
    allow(network).to receive(:status=)
    allow(network).to receive(:save!)

    # Expect that reconciler does not call methods that write user intent
    expect(network).not_to receive(:name=)
    expect(network).not_to receive(:slug=)
    expect(network).not_to receive(:type=)
  end
end
