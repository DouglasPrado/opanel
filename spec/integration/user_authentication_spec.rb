require "rails_helper"

RSpec.describe AuthenticateUser, type: :integration do
  let(:password) { "hunter2-hunter2-hunter2" }
  let!(:user) { create(:user, email: "person@example.test", password: password) }

  def authenticate(email: "person@example.test", secret: password, ip: "203.0.113.5")
    described_class.call(email: email, password: secret, ip: ip, user_agent: "RSpec")
  end

  describe "a correct credential" do
    it "authenticates and opens a session" do
      result = authenticate

      expect(result).to be_success
      expect(result.value.fetch(:user)).to eq(user)
      expect(result.value.fetch(:session).user_id).to eq(user.id)
    end

    it "matches the address case-insensitively and ignores surrounding space" do
      expect(authenticate(email: "  Person@Example.TEST ")).to be_success
    end

    it "returns the raw token once and persists only its digest — AC3" do
      result = authenticate
      token = result.value.fetch(:session_token)

      expect(result.value.fetch(:session).token_digest).to eq(Session.digest(token))
      expect(Session.pluck(:token_digest)).to all(match(/\A[0-9a-f]{64}\z/))
      expect(Session.pluck(:token_digest)).not_to include(token)
    end

    it "records the authentication context as `password` until MFA exists" do
      expect(authenticate.value.fetch(:session).mfa_level).to eq("password")
    end

    it "sets both lifetimes at creation" do
      travel_to Time.utc(2026, 5, 1, 10, 0, 0) do
        session = authenticate.value.fetch(:session)

        expect(session.expires_at).to be_within(1.second).of(Session::ABSOLUTE_TTL.from_now)
        expect(session.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    it "opens a second session without disturbing the first" do
      first = authenticate.value.fetch(:session)
      second = authenticate.value.fetch(:session)

      expect(second).not_to eq(first)
      expect(first.reload).to be_active
      expect(user.sessions.count).to eq(2)
    end

    it "gives every session a distinct token digest, enforced by the database" do
      session = authenticate.value.fetch(:session)

      expect {
        create(:session, user: user, token_digest: session.token_digest)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "a credential that does not authenticate" do
    it "refuses an unknown address" do
      expect(authenticate(email: "nobody@example.test").code).to eq("INVALID_CREDENTIALS")
    end

    it "refuses a wrong password" do
      expect(authenticate(secret: "#{password}-wrong").code).to eq("INVALID_CREDENTIALS")
    end

    it "refuses a SUSPENDED account" do
      user.update!(status: "SUSPENDED")

      expect(authenticate.code).to eq("INVALID_CREDENTIALS")
    end

    it "refuses a DELETED_PENDING account, which is terminal for authentication" do
      user.update!(status: "DELETED_PENDING")

      expect(authenticate.code).to eq("INVALID_CREDENTIALS")
    end

    it "opens no session on any refusal" do
      authenticate(email: "nobody@example.test")
      authenticate(secret: "#{password}-wrong")

      expect(Session.count).to eq(0)
    end

    it "answers every refusal identically — AC6 at the command boundary" do
      user.update!(status: "SUSPENDED")
      suspended = authenticate
      user.update!(status: "ACTIVE")

      answers = [ authenticate(email: "nobody@example.test"), authenticate(secret: "no"), suspended ]

      expect(answers.map { |result| [ result.code, result.message ] }.uniq.length).to eq(1)
    end
  end

  describe "rehash on login" do
    it "upgrades a digest produced with weaker parameters, after verifying it" do
      weaker = Argon2::Password.new(m_cost: 12, t_cost: 2, p_cost: 1).create(password)
      user.update_column(:password_digest, weaker)

      expect(authenticate).to be_success
      expect(user.reload.password_digest).not_to eq(weaker)
      expect(Opanel::PasswordHashing.needs_rehash?(user.password_digest)).to be(false)
      expect(Opanel::PasswordHashing.verify(user.password_digest, password)).to be(true)
    end

    it "leaves a current digest alone" do
      before = user.password_digest

      authenticate

      expect(user.reload.password_digest).to eq(before)
    end

    it "rehashes outside the session-creation transaction" do
      weaker = Argon2::Password.new(m_cost: 12, t_cost: 2, p_cost: 1).create(password)
      user.update_column(:password_digest, weaker)

      baseline = ActiveRecord::Base.connection.open_transactions
      depth = nil
      allow(Opanel::PasswordHashing).to receive(:create).and_wrap_original do |original, *arguments|
        depth = ActiveRecord::Base.connection.open_transactions
        original.call(*arguments)
      end

      authenticate

      expect(depth).to eq(baseline)
    end

    it "does not rehash a credential that failed" do
      user.update_column(:password_digest, Argon2::Password.new(m_cost: 12, t_cost: 2, p_cost: 1).create(password))
      before = user.password_digest

      authenticate(secret: "#{password}-wrong")

      expect(user.reload.password_digest).to eq(before)
    end
  end

  describe "the constraints, against a writer that bypasses the model" do
    it "refuses a token digest that is not 64 hex characters" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO sessions (id, user_id, token_digest, expires_at, last_seen_at,
                                mfa_level, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', '#{user.id}', '#{'Z' * 64}',
                  now(), now(), 'password', now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /sessions_token_digest_is_sha256/)
    end

    it "refuses an unknown mfa level" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO sessions (id, user_id, token_digest, expires_at, last_seen_at,
                                mfa_level, created_at, updated_at)
          VALUES ('#{Opanel::Identifier.generate}', '#{user.id}', '#{'a' * 64}',
                  now(), now(), 'totp', now(), now())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /sessions_mfa_level/)
    end

    it "removes a user's sessions with the user" do
      authenticate
      user.destroy!

      expect(Session.count).to eq(0)
    end
  end
end
