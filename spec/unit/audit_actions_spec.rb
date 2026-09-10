require "rails_helper"

# The Required Test the Story names: *"unit: sanitizador por allowlist; **nomes de
# ação estáveis**"*.
#
# Stability is the property that makes a trail readable years later. An action
# name is a contract with every future query, dashboard and incident review: doc
# 09 §15.1 asks for *"nome estável"* precisely because renaming one silently
# orphans everything already written under the old name.
RSpec.describe "the audit action names", type: :unit do
  # Written out rather than read from the constant. A spec that iterates the thing
  # it checks proves only that the constant equals itself; transcribing the list
  # means a rename has to be a deliberate change in two places, which is what
  # "stable" has to cost.
  EXPECTED = {
    installation_bootstrapped: "installation.bootstrapped",
    team_created: "team.created",
    team_member_suspended: "team.member.suspended",
    team_ownership_recovery_required: "team.ownership.recovery_required",
    user_registered: "user.registered",
    user_signed_in: "user.signed_in",
    user_sign_in_failed: "user.sign_in_failed",
    session_revoked: "session.revoked",
    instance_role_granted: "instance_role.granted",
    instance_role_revoked: "instance_role.revoked",
    authorization_denied: "authorization.denied",
    project_created: "project.created",
    project_updated: "project.updated",
    project_archived: "project.archived"
  }.freeze

  it "are exactly these, and renaming one is a change to this file too" do
    expect(AuditLog::ACTIONS).to eq(EXPECTED)
  end

  it "are namespaced, so a trail can be filtered by area" do
    AuditLog::ACTIONS.each_value do |name|
      expect(name).to match(/\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\z/),
        "#{name} is not a namespaced, lower-case action name"
    end
  end

  # The database agrees, so an action name cannot enter by another route.
  it "are the shape the database enforces" do
    expect {
      AuditLog.new(
        actor_type: "SYSTEM", action: "SomethingArbitrary", resource_type: "User",
        request_id: "r", correlation_id: "c", result: "SUCCESS", created_at: Time.current
      ).save!(validate: false)
    }.to raise_error(ActiveRecord::StatementInvalid, /audit_logs_action_is_namespaced/)
  end

  it "are unique, so two actions cannot collapse into one" do
    expect(AuditLog::ACTIONS.values.uniq.length).to eq(AuditLog::ACTIONS.length)
  end

  # Every action a Command can ask for must exist, or `AuditTrail.record` raises
  # at the moment the trail is most needed.
  it "cover every action the application asks for" do
    asked = Dir.glob(Rails.root.join("app/**/*.rb")) + Dir.glob(Rails.root.join("lib/opanel/**/*.rb"))
    requested = asked.flat_map { |path| File.read(path).scan(/action:\s*:([a-z_]+)/) }.flatten.uniq

    audit_requests = requested.select { |name| AuditLog::ACTIONS.key?(name.to_sym) }

    expect(audit_requests).not_to be_empty, "no Command asks for an audit action — the scan found nothing"
    expect(audit_requests.map(&:to_sym) - AuditLog::ACTIONS.keys).to be_empty
  end

  describe "an unregistered action" do
    it "is refused loudly rather than written under a made-up name" do
      expect {
        AuditTrail.record(action: :something_nobody_registered, actor: nil, resource: create(:user))
      }.to raise_error(ArgumentError, /not a registered audit action/)
    end
  end

  describe "the instance-event list" do
    it "names only actions that exist" do
      expect(AuditLog::ACTIONS.values).to include(*AuditLog::INSTANCE_ACTIONS)
    end

    # The inverse of AC10: an action about a Team must not be able to skip its
    # `team_id` by being wrongly listed as an installation event.
    it "excludes every action that is about a Team" do
      tenant_scoped = [
        AuditLog::ACTIONS[:team_created],
        AuditLog::ACTIONS[:team_member_suspended],
        AuditLog::ACTIONS[:team_ownership_recovery_required]
      ]

      expect(AuditLog::INSTANCE_ACTIONS & tenant_scoped).to be_empty
    end
  end
end
