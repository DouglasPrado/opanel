require "rails_helper"

# Credentials come from the environment, never from a versioned file. This is the
# cheap, always-on check; the full secret scan over the tree and the branch history
# arrives with M00-10.
RSpec.describe "database configuration", type: :security do
  let(:source) { Rails.root.join("config/database.yml").read }

  it "reads every credential from the environment" do
    credential_lines = source.lines.grep(/^\s*(username|password):/)

    expect(credential_lines).not_to be_empty
    credential_lines.each do |line|
      expect(line).to match(/ENV[\[.]/),
        "config/database.yml hardcodes a credential: #{line.strip.inspect}"
    end
  end

  it "does not embed a connection URL with inline credentials" do
    expect(source).not_to match(%r{postgres(ql)?://[^\s:]+:[^\s@]+@}),
      "config/database.yml embeds a connection URL carrying a password"
  end

  it "keeps development, test and ci on separate databases" do
    databases = %w[development test ci production].map do |environment|
      ActiveRecord::Base.configurations.configs_for(env_name: environment, name: "primary").database
    end

    expect(databases.uniq.length).to eq(databases.length),
      "environments must not share a database: #{databases.inspect}"
  end

  it "does not leak a credential through a classified connection failure" do
    error = StandardError.new(
      'connection to server failed: FATAL:  password authentication failed for user "opanel"; password=hunter2'
    )

    result = Opanel::DatabaseConnection.classify(error)

    expect(result.detail).not_to include("hunter2")
    expect(result.cause).to eq(:authentication_failed)
  end
end
