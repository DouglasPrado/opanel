require "rails_helper"

RSpec.describe "GET /up", type: :request do
  let(:body) { response.parsed_body }

  describe "when everything is reachable" do
    before { get "/up" }

    it "answers 200" do
      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("ok")
    end

    it "reports the application, the database and the queue separately" do
      expect(body["checks"].keys).to match_array(%w[application database queue])
      expect(body["checks"].values.map { |check| check["status"] }).to all(eq("ok"))
    end

    it "answers a health checker that is not a browser" do
      # A load balancer sends no user agent, and must never be refused for it.
      get "/up", headers: { "HTTP_USER_AGENT" => "" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "what it must not reveal" do
    before { get "/up" }

    it "leaks no version, hostname, connection string or resource count" do
      raw = response.body

      expect(raw).not_to include(Rails.version)
      expect(raw).not_to include(RUBY_VERSION)
      expect(raw).not_to include(ActiveRecord::Base.connection_db_config.database)
      expect(raw).not_to match(/postgres(ql)?:\/\//)
      expect(raw).not_to match(/\b(hostname|host|port|adapter|pool)\b/i)
    end

    it "answers with the vocabulary of a health check and nothing else" do
      expect(body.keys).to match_array(%w[status checks])
      body["checks"].each_value { |check| expect(check.keys - %w[status cause]).to be_empty }
    end
  end

  describe "when a dependency is unavailable" do
    # The application must never claim to be healthy while something it needs is
    # not (Annex B §20): a load balancer that keeps routing to it turns one broken
    # dependency into a broken product.
    before do
      allow(Opanel::DatabaseConnection).to receive(:check)
        .and_return(Opanel::DatabaseConnection::Result.new(cause: :host_unreachable, detail: "irrelevant"))
      get "/up"
    end

    it "answers 503 so a load balancer stops sending traffic" do
      expect(response).to have_http_status(:service_unavailable)
      expect(body["status"]).to eq("unavailable")
    end

    it "names the classified cause rather than a generic timeout" do
      expect(body.dig("checks", "database", "status")).to eq("unavailable")
      expect(body.dig("checks", "database", "cause")).to eq("host_unreachable")
    end

    it "still reports the queue and the application separately" do
      expect(body.dig("checks", "application", "status")).to eq("ok")
      expect(body["checks"]).to have_key("queue")
    end

    it "reports the cause but not the adapter's message, which can name a host" do
      expect(response.body).not_to include("irrelevant")
    end
  end

  describe "when the queue is unavailable but the database is not" do
    before do
      allow(SolidQueue::Job).to receive(:where).and_raise(
        ActiveRecord::StatementInvalid, "relation \"solid_queue_jobs\" does not exist"
      )
      get "/up"
    end

    it "degrades the queue without blaming the database" do
      expect(response).to have_http_status(:service_unavailable)
      expect(body.dig("checks", "database", "status")).to eq("ok")
      expect(body.dig("checks", "queue", "status")).to eq("unavailable")
    end
  end
end
