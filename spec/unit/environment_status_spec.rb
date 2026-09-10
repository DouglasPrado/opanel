require "rails_helper"

# Status transitions and the state machine of doc 09 §17.
RSpec.describe Environment, ".can_transition_to?" do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }

  it "allows PROVISIONING → READY" do
    env = create(:environment, project: project, cluster: cluster, status: "PROVISIONING")
    expect(env.can_transition_to?("READY")).to be true
  end

  it "allows PROVISIONING → DEGRADED" do
    env = create(:environment, project: project, cluster: cluster, status: "PROVISIONING")
    expect(env.can_transition_to?("DEGRADED")).to be true
  end

  it "allows PROVISIONING → PAUSED" do
    env = create(:environment, project: project, cluster: cluster, status: "PROVISIONING")
    expect(env.can_transition_to?("PAUSED")).to be true
  end

  it "refuses PROVISIONING → DELETING" do
    env = create(:environment, project: project, cluster: cluster, status: "PROVISIONING")
    expect(env.can_transition_to?("DELETING")).to be false
  end

  it "allows READY → DEGRADED" do
    env = create(:environment, project: project, cluster: cluster, status: "READY")
    expect(env.can_transition_to?("DEGRADED")).to be true
  end

  it "allows READY → DELETING" do
    env = create(:environment, project: project, cluster: cluster, status: "READY")
    expect(env.can_transition_to?("DELETING")).to be true
  end

  it "allows DEGRADED → READY" do
    env = create(:environment, project: project, cluster: cluster, status: "DEGRADED")
    expect(env.can_transition_to?("READY")).to be true
  end

  it "allows DEGRADED → PAUSED" do
    env = create(:environment, project: project, cluster: cluster, status: "DEGRADED")
    expect(env.can_transition_to?("PAUSED")).to be true
  end

  it "allows DEGRADED → DELETING" do
    env = create(:environment, project: project, cluster: cluster, status: "DEGRADED")
    expect(env.can_transition_to?("DELETING")).to be true
  end

  it "allows PAUSED → READY" do
    env = create(:environment, project: project, cluster: cluster, status: "PAUSED")
    expect(env.can_transition_to?("READY")).to be true
  end

  it "allows PAUSED → PROVISIONING" do
    env = create(:environment, project: project, cluster: cluster, status: "PAUSED")
    expect(env.can_transition_to?("PROVISIONING")).to be true
  end

  it "allows PAUSED → DELETING" do
    env = create(:environment, project: project, cluster: cluster, status: "PAUSED")
    expect(env.can_transition_to?("DELETING")).to be true
  end

  it "refuses DELETING → any state (terminal)" do
    env = create(:environment, project: project, cluster: cluster, status: "DELETING")
    (Environment::STATUSES - [ Environment::DELETING ]).each do |status|
      expect(env.can_transition_to?(status)).to be false
    end
  end
end

RSpec.describe Environment, "type predicates" do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }

  Environment::TYPES.each do |env_type|
    it "answers true for #{env_type}?" do
      env = create(:environment, project: project, cluster: cluster, type: env_type)
      expect(env.send("#{env_type.downcase}?")).to be true
    end

    it "answers false for #{env_type}? when type is different" do
      env = create(:environment, project: project, cluster: cluster, type: "DEVELOPMENT")
      expect(env.send("#{env_type.downcase}?")).to be false if env_type != "DEVELOPMENT"
    end
  end
end

RSpec.describe Environment, "status predicates" do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:cluster) { create(:cluster, team: team) }

  Environment::STATUSES.each do |st|
    it "answers true for #{st}?" do
      env = create(:environment, project: project, cluster: cluster, status: st)
      expect(env.send("#{st.downcase}?")).to be true
    end
  end
end
