require "rails_helper"

# Real PostgreSQL (Annex D §5): the constraints below are the point, and a
# constraint asserted against a stub is a constraint nobody has.
RSpec.describe RegisterUser, type: :integration do
  let(:password) { "hunter2-hunter2-hunter2" }

  def register(email: "new-person@example.test", display_name: "New Person", ip: "203.0.113.5")
    described_class.call(email: email, password: password, display_name: display_name,
      ip: ip, user_agent: "RSpec")
  end

  describe "the happy path" do
    it "creates the user and signs them in, in one transaction" do
      result = register

      expect(result).to be_success
      expect(result.value.fetch(:user)).to be_persisted
      expect(result.value.fetch(:session)).to be_persisted
      expect(result.value.fetch(:session).user_id).to eq(result.value.fetch(:user).id)
    end

    it "returns the raw token once and stores only its digest" do
      token = register.value.fetch(:session_token)
      session = Session.sole

      expect(token).to be_present
      expect(session.token_digest).to eq(Session.digest(token))
      expect(session.token_digest).not_to eq(token)
      expect(Session.where(token_digest: token)).to be_empty
    end

    it "normalizes the address" do
      expect(register(email: "  New-Person@Example.TEST ").value.fetch(:user).email)
        .to eq("new-person@example.test")
    end

    it "gives both rows ULID identifiers, prefixed only at the boundary" do
      result = register

      expect(result.value.fetch(:user).id).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
      expect(result.value.fetch(:session).id).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
    end

    it "starts the user ACTIVE with no verified address" do
      user = register.value.fetch(:user)

      expect(user.status).to eq("ACTIVE")
      expect(user.email_verified_at).to be_nil
    end

    it "records the device metadata the session list shows" do
      session = register.value.fetch(:session)

      expect(session.ip_address.to_s).to eq("203.0.113.5")
      expect(session.user_agent).to eq("RSpec")
      expect(session.mfa_level).to eq("password")
    end
  end

  describe "an address that is already taken" do
    it "refuses an existing ACTIVE account without confirming it exists" do
      create(:user, email: "taken@example.test")

      result = register(email: "taken@example.test")

      expect(result).to be_failure
      expect(result.code).to eq("EMAIL_UNAVAILABLE")
      expect(User.where(email: "taken@example.test").count).to eq(1)
    end

    it "refuses the same way for SUSPENDED and DELETED_PENDING" do
      # doc 09 §3.1: an address held by an account in retention is not reusable,
      # and doc 10 UC-001: the refusal must not tell an anonymous caller which
      # state that account is in.
      responses = %i[suspended deleted_pending].map do |trait|
        create(:user, trait, email: "held-#{trait}@example.test")
        register(email: "held-#{trait}@example.test")
      end

      expect(responses.map(&:code).uniq).to eq([ "EMAIL_UNAVAILABLE" ])
      expect(responses.map(&:message).uniq.length).to eq(1)
    end

    it "produces the identical refusal for every status, including a free address that races" do
      create(:user, email: "taken@example.test")
      create(:user, :deleted_pending, email: "retained@example.test")

      messages = [ register(email: "taken@example.test"), register(email: "retained@example.test") ]

      expect(messages.map { |result| [ result.code, result.message ] }.uniq.length).to eq(1)
    end

    it "loses a race on the unique index without raising" do
      # The check-then-insert window is real. The database is what closes it, and
      # the rescue has to produce the same neutral answer the pre-check does.
      allow(User).to receive(:exists?).and_return(false)
      create(:user, email: "raced@example.test")

      result = register(email: "raced@example.test")

      expect(result).to be_failure
      expect(result.code).to eq("EMAIL_UNAVAILABLE")
    end

    it "matches case-insensitively, because the column is citext" do
      create(:user, email: "Mixed@Example.test")

      expect(register(email: "mixed@example.TEST").code).to eq("EMAIL_UNAVAILABLE")
    end
  end

  describe "input the policy refuses" do
    it "refuses a weak password with a message that states the rule" do
      result = described_class.call(email: "weak@example.test", password: "short",
        display_name: "Weak", ip: "203.0.113.5", user_agent: "RSpec")

      expect(result.code).to eq("VALIDATION_ERROR")
      expect(result.message).to match(/12 characters/)
      expect(User.count).to eq(0)
    end

    it "refuses a malformed address" do
      expect(register(email: "not-an-address").code).to eq("VALIDATION_ERROR")
    end

    it "refuses a blank display name" do
      expect(register(display_name: "   ").code).to eq("VALIDATION_ERROR")
    end

    it "writes nothing at all when it refuses" do
      register(email: "not-an-address")

      expect(User.count).to eq(0)
      expect(Session.count).to eq(0)
    end
  end

  describe "the constraints, against a writer that bypasses the model" do
    it "refuses a non-ULID identifier" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO users (id, email, display_name, password_digest, status, created_at, updated_at)
          VALUES ('not-a-ulid', 'bypass@example.test', 'Bypass', '$argon2id$x', 'ACTIVE', now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /users_id_is_ulid/)
    end

    it "refuses a digest that is not Argon2id" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO users (id, email, display_name, password_digest, status, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', 'bypass@example.test', 'Bypass',
                  '$2a$12$plainly-bcrypt', 'ACTIVE', now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /users_password_digest_is_argon2id/)
    end

    it "refuses an unknown status" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO users (id, email, display_name, password_digest, status, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', 'bypass@example.test', 'Bypass',
                  '$argon2id$x', 'DELETED', now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /users_status/)
    end

    it "refuses a duplicate address at the database, not only in the model" do
      create(:user, email: "unique@example.test")

      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO users (id, email, display_name, password_digest, status, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', 'UNIQUE@example.test', 'Bypass',
                  '$argon2id$x', 'ACTIVE', now(), now())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "keeps the uniqueness unconditional, which is what stops silent reuse" do
      # A partial unique excluding DELETED_PENDING would let a retained address be
      # taken over in silence (doc 09 §3.1).
      index = ActiveRecord::Base.connection.indexes("users").find { |candidate| candidate.columns == [ "email" ] }

      expect(index).to be_present
      expect(index.unique).to be(true)
      expect(index.where).to be_nil
    end
  end

  describe "the transaction boundary" do
    it "performs the Argon2 hashing before opening the transaction" do
      # ~60 ms of CPU inside a transaction is a connection held for no reason,
      # and Annex I forbids doing slow work while a lock is open.
      # The suite itself runs inside a transaction, so the depth is compared with
      # the baseline rather than asked whether one is open at all.
      baseline = ActiveRecord::Base.connection.open_transactions
      depth = nil
      allow(Opanel::PasswordHashing).to receive(:create).and_wrap_original do |original, *arguments|
        depth = ActiveRecord::Base.connection.open_transactions
        original.call(*arguments)
      end

      register

      expect(depth).to eq(baseline)
    end
  end
end
