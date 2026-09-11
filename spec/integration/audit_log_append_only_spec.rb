require "rails_helper"

# AC1 and AC2: the record is append-only, and no application code rewrites it.
#
# Three layers, because each covers the others' failure: the model refuses, the
# database refuses the shape of a rewrite, and a scan of the application asserts
# nobody tries. The third is the one that survives somebody removing the first.
RSpec.describe "an audit record is append-only", type: :integration do
  let(:owner) { create(:user) }
  let(:team) { create(:team, owner: owner) }
  let!(:record) do
    AuditLog.create!(
      team_id: team.id, actor_type: "USER", actor_id: owner.id,
      action: AuditLog::ACTIONS[:team_created], resource_type: "Team", resource_id: team.id,
      request_id: "req_test", correlation_id: "corr_test", result: "SUCCESS",
      created_at: Time.current
    )
  end

  describe "the model" do
    it "refuses update" do
      expect { record.update(action: AuditLog::ACTIONS[:session_revoked]) }
        .to raise_error(AuditLog::Immutable, /append-only/)
    end

    it "refuses update!" do
      expect { record.update!(result: "FAILED") }.to raise_error(AuditLog::Immutable)
    end

    it "refuses destroy" do
      expect { record.destroy }.to raise_error(AuditLog::Immutable)
      expect(AuditLog.exists?(record.id)).to be(true)
    end

    it "is readonly once persisted, so `save` cannot rewrite it either" do
      record.result = "FAILED"

      expect { record.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(record.reload.result).to eq("SUCCESS")
    end
  end

  describe "the database" do
    # `revision = 1` exists for this: it gives an UPDATE something it must change,
    # which is what makes immutability expressible as a CHECK. A trigger would
    # have been the obvious tool and would have vanished from every database
    # loaded from `db/schema.rb` — the defect recorded as SC-17.
    it "refuses an UPDATE that touches the revision, even with the model bypassed" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          UPDATE audit_logs SET revision = 2
          WHERE id = #{ActiveRecord::Base.connection.quote(record.id)}
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /audit_logs_are_append_only/)
    end

    # `readonly?` reaches further than expected: even `update_columns`, which
    # normally skips validations and callbacks, is refused.
    it "refuses update_columns too, which usually bypasses the model" do
      expect { record.update_columns(result: "FAILED") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(record.reload.result).to eq("SUCCESS")
    end

    # Stated plainly rather than claimed away. A CHECK constrains the shape of a
    # row, not who may write it: raw SQL against another column does reach the
    # database. The honest defence is the code scan below plus table privileges,
    # which are an operational concern and not something a migration can assert.
    # Saying so is better than implying the table is tamper-proof.
    it "does not pretend to stop raw SQL against another column" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          UPDATE audit_logs SET result = 'FAILED'
          WHERE id = #{ActiveRecord::Base.connection.quote(record.id)}
        SQL
      }.not_to raise_error

      expect(record.reload.result).to eq("FAILED")
    end
  end

  # AC2, as a property of the application rather than of one model. This is what
  # notices somebody adding `audit_log.update!` in a Command next year.
  describe "the application code" do
    # The scan, as a callable. Both examples below drive **this**, so the control
    # cannot pass against a copy of the logic — the defect this Milestone produced
    # three times before.
    def rewrites_the_trail(sources)
      sources.select { |_name, source|
        source.match?(/AuditLog[^\n]*\.(update|destroy|delete|update_all|delete_all|update_columns)\b/) ||
          source.match?(/audit_log(?:s)?\s*\.\s*(update|destroy|delete|update_all|delete_all|update_columns)\b/) ||
          source.match?(/UPDATE\s+audit_logs|DELETE\s+FROM\s+audit_logs/i)
      }.keys
    end

    # `lib/opanel/**` is included because this Story made `Opanel::Authorization`
    # an audit writer: scanning only `app/**` would have left the newest writer
    # outside the check.
    def application_sources
      paths = Dir.glob(Rails.root.join("app/**/*.rb")) + Dir.glob(Rails.root.join("lib/opanel/**/*.rb"))

      paths.reject { |path| path.end_with?("app/models/audit_log.rb") }
        .to_h { |path| [ path.sub("#{Rails.root}/", ""), File.read(path) ] }
    end

    it "never updates or deletes an audit record" do
      sources = application_sources

      expect(sources.keys).to include("lib/opanel/authorization.rb"),
        "the scan is not reading the audit writers it is meant to cover"

      expect(rewrites_the_trail(sources)).to be_empty,
        "these files rewrite the audit trail: #{rewrites_the_trail(sources).join(', ')}"
    end

    # Drives the real scan against planted sources, one per way of writing it.
    it "sees a violation however it is spelled" do
      planted = {
        "a.rb" => "AuditLog.where(id: x).delete_all",
        "b.rb" => "AuditLog.find(id).update!(result: 'FAILED')",
        "c.rb" => "audit_log.destroy",
        "d.rb" => "entry.update_columns(result: 'FAILED') # audit_logs",
        "e.rb" => "connection.execute('DELETE FROM audit_logs WHERE id = 1')"
      }

      # `d.rb` is the one the receiver-based patterns miss; the SQL pattern is
      # what catches `e.rb`. Naming which is caught by what keeps the assertion
      # from passing for the wrong reason.
      expect(rewrites_the_trail(planted)).to include("a.rb", "b.rb", "c.rb", "e.rb")
    end

    it "does not report ordinary code" do
      innocent = {
        "f.rb" => "AuditLog.create!(action: 'team.created')",
        "g.rb" => "AuditLog.for_request(request_id).limit(10)",
        "h.rb" => "team.update!(name: 'New')"
      }

      expect(rewrites_the_trail(innocent)).to be_empty
    end
  end
end
