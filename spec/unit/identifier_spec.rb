require "rails_helper"

# ADR-0002 is the decision this proves: one identifier format for the database,
# the API, the events, the MCP resource URIs and the Swarm labels. AC11.
RSpec.describe Opanel::Identifier, type: :unit do
  describe ".generate" do
    it "produces a 26-character Crockford Base32 ULID" do
      expect(described_class.generate).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
    end

    it "excludes the four ambiguous Crockford letters" do
      sample = Array.new(200) { described_class.generate }.join

      expect(sample).not_to match(/[ILOU]/)
    end

    it "encodes the current time, so two ids minutes apart sort by time" do
      earlier = travel_to(Time.utc(2026, 1, 1, 0, 0, 0)) { described_class.generate }
      later = travel_to(Time.utc(2026, 1, 1, 0, 5, 0)) { described_class.generate }

      expect(earlier).to be < later
    end

    it "stays monotonic inside one millisecond rather than redrawing entropy" do
      # The clock is frozen, so every id below shares a timestamp. ADR-0002 §1
      # requires them to keep increasing anyway; a redraw would sort randomly.
      ids = travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) { Array.new(50) { described_class.generate } }

      expect(ids).to eq(ids.sort)
      expect(ids.uniq.length).to eq(50)
    end

    it "produces distinct values across many calls" do
      ids = Array.new(2_000) { described_class.generate }

      expect(ids.uniq.length).to eq(2_000)
    end
  end

  describe "the prefix registry" do
    it "registers every type ADR-0002 §3 lists" do
      expect(described_class::PREFIXES.values).to include(
        "usr", "team", "prj", "env", "svc", "rel", "art", "bld", "dep", "op",
        "sec", "sv", "dom", "cert", "cv", "cl", "node", "enr", "bkp", "snap",
        "rst", "apr", "agc", "tok", "inc", "alr"
      )
    end

    it "registers `ses` for Session under the ADR's own extension rule" do
      expect(described_class::PREFIXES.fetch(:session)).to eq("ses")
    end

    it "registers `tm` for TeamMember under the same extension rule" do
      expect(described_class::PREFIXES.fetch(:team_member)).to eq("tm")
    end

    it "holds no duplicate prefix" do
      expect(described_class.validate_registry!).to be(true)
    end

    it "raises a duplicate prefix by name rather than silently colliding" do
      colliding = described_class::PREFIXES.merge(imposter: "usr")

      expect { described_class.validate_registry!(colliding) }
        .to raise_error(Opanel::Identifier::DuplicatePrefixError, /usr/)
    end
  end

  describe ".external" do
    it "prefixes the ULID with the registered type prefix" do
      id = described_class.generate

      expect(described_class.external(:user, id)).to eq("usr_#{id}")
    end

    it "returns nil for a nil id rather than a prefix with nothing behind it" do
      expect(described_class.external(:user, nil)).to be_nil
    end

    it "refuses an unregistered type" do
      expect { described_class.external(:nonexistent, described_class.generate) }
        .to raise_error(Opanel::Identifier::UnknownType)
    end
  end

  describe ".parse" do
    let(:id) { described_class.generate }

    it "returns the bare ULID of a correctly prefixed identifier" do
      expect(described_class.parse(:session, "ses_#{id}")).to eq(id)
    end

    it "rejects a prefix belonging to another type as VALIDATION_ERROR, never NOT_FOUND" do
      # ADR-0002 §4. Answering NOT_FOUND would make a type confusion look like an
      # authorization outcome, and would let a caller probe which ids exist.
      error = nil
      begin
        described_class.parse(:session, "usr_#{id}")
      rescue Opanel::Identifier::InvalidIdentifier => raised
        error = raised
      end

      expect(error).not_to be_nil
      expect(error.code).to eq("VALIDATION_ERROR")
    end

    it "rejects an unknown prefix" do
      expect { described_class.parse(:session, "zzz_#{id}") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "rejects a bare ULID with no prefix" do
      expect { described_class.parse(:session, id) }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "rejects non-Crockford characters" do
      expect { described_class.parse(:session, "ses_#{'I' * 26}") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "rejects the wrong length" do
      expect { described_class.parse(:session, "ses_#{id[0..-2]}") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "rejects nil and an empty value" do
      expect { described_class.parse(:session, nil) }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
      expect { described_class.parse(:session, "") }
        .to raise_error(Opanel::Identifier::InvalidIdentifier)
    end

    it "checks shape only — it is not an authorization check" do
      # Annex C §7.3. Stated as an assertion so the intent survives: parse
      # answers "is this the right kind of id", never "may you have it".
      other_users_id = described_class.generate

      expect(described_class.parse(:session, "ses_#{other_users_id}")).to eq(other_users_id)
    end
  end
end
