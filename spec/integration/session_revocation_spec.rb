require "rails_helper"

RSpec.describe "session revocation and listing", type: :integration do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  def external(session) = Opanel::Identifier.external(:session, session.id)

  describe RevokeSession do
    it "revokes a session the caller owns" do
      session = create(:session, user: user)

      result = described_class.call(actor: user, session_id: external(session))

      expect(result).to be_success
      expect(session.reload.revoked_at).to be_present
      expect(session.reload).not_to be_active
    end

    it "is idempotent: revoking twice does not move the timestamp" do
      session = create(:session, user: user)

      described_class.call(actor: user, session_id: external(session))
      first = session.reload.revoked_at
      expect(described_class.call(actor: user, session_id: external(session))).to be_success

      expect(session.reload.revoked_at).to eq(first)
    end

    it "answers NOT_FOUND for another user's session, never FORBIDDEN" do
      # Cross-account negative (Annex C §7.3). FORBIDDEN would confirm the id
      # exists, which is exactly the disclosure the scoped query removes.
      session = create(:session, user: other)

      result = described_class.call(actor: user, session_id: external(session))

      expect(result.code).to eq("NOT_FOUND")
      expect(session.reload.revoked_at).to be_nil
    end

    it "scopes the lookup in the query rather than fetching then checking" do
      session = create(:session, user: other)

      expect(Session).not_to receive(:find)
      expect(Session).not_to receive(:find_by_id)

      described_class.call(actor: user, session_id: external(session))
    end

    it "answers NOT_FOUND for a well-formed id that belongs to nobody" do
      result = described_class.call(actor: user,
        session_id: Opanel::Identifier.external(:session, Opanel::Identifier.generate))

      expect(result.code).to eq("NOT_FOUND")
    end

    it "answers VALIDATION_ERROR for an identifier of another type — ADR-0002 §4" do
      session = create(:session, user: user)
      wrong_type = Opanel::Identifier.external(:user, session.id)

      expect(described_class.call(actor: user, session_id: wrong_type).code).to eq("VALIDATION_ERROR")
      expect(session.reload.revoked_at).to be_nil
    end

    it "answers VALIDATION_ERROR for a malformed identifier" do
      expect(described_class.call(actor: user, session_id: "ses_not-a-ulid").code).to eq("VALIDATION_ERROR")
      expect(described_class.call(actor: user, session_id: nil).code).to eq("VALIDATION_ERROR")
    end
  end

  describe UserSessions do
    it "lists the caller's sessions with the metadata the page shows — AC5" do
      session = create(:session, user: user, ip_address: "198.51.100.7", user_agent: "Firefox")

      entry = described_class.call(user: user, current_session_id: session.id).sole

      expect(entry.id).to eq(external(session))
      expect(entry.ip_address).to eq("198.51.100.7")
      expect(entry.user_agent).to eq("Firefox")
      expect(entry.last_seen_at).to be_present
      expect(entry.created_at).to be_present
      expect(entry.expires_at).to be_present
      expect(entry.current).to be(true)
    end

    it "marks only the caller's current session as current" do
      current = create(:session, user: user)
      create(:session, user: user)

      entries = described_class.call(user: user, current_session_id: current.id)

      expect(entries.select(&:current).map(&:id)).to eq([ external(current) ])
    end

    it "lists nothing belonging to another user" do
      create(:session, user: other)

      expect(described_class.call(user: user)).to be_empty
    end

    it "orders active sessions before revoked ones, newest first" do
      old_active = create(:session, user: user, created_at: 3.days.ago)
      new_active = create(:session, user: user, created_at: 1.hour.ago)
      revoked = create(:session, :revoked, user: user, created_at: 1.minute.ago)

      ids = described_class.call(user: user).map(&:id)

      expect(ids).to eq([ new_active, old_active, revoked ].map { |record| external(record) })
    end

    it "reports whether each entry still grants access" do
      create(:session, user: user)
      create(:session, :revoked, user: user)

      expect(described_class.call(user: user).map(&:active)).to contain_exactly(true, false)
    end

    it "is bounded, because an unbounded collection load is not a read" do
      expect(described_class::LIMIT).to eq(100)

      create_list(:session, 3, user: user)
      stub_const("UserSessions::LIMIT", 2)

      expect(described_class.call(user: user).length).to eq(2)
    end

    it "never loads the token digest, so it cannot reach a prop by accident" do
      create(:session, user: user)

      entry = described_class.call(user: user).sole

      expect(entry.to_h.keys).not_to include(:token_digest)
      expect(entry.to_h.values.map(&:to_s).join).not_to include(Session.sole.token_digest)
    end

    it "returns an empty list rather than nil for a user with no sessions" do
      expect(described_class.call(user: user)).to eq([])
    end
  end
end
