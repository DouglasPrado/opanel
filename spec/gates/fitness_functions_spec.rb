require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require "date"
require_relative "../../lib/gates/fitness_functions"

# Ten functions, ten planted violations.
#
# Most of these pass vacuously today — there is no MCP adapter, no reconciler, no
# serializer — and a vacuous pass is indistinguishable from a broken rule unless
# somebody proves the rule can fail. That is what this file is for. Each function
# is given a violation it must catch *and* a compliant case it must accept, so
# none is passing by refusing everything.
RSpec.describe Opanel::Gates::FitnessFunctions do
  FITNESS = Opanel::Gates::FitnessFunctions

  # Builds a throwaway repository containing exactly the files under test.
  def in_repository(files, metadata: {})
    Dir.mktmpdir do |root|
      files.each do |path, content|
        full = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end

      metadata_path = File.join(root, "config/architecture/fitness.yml")
      FileUtils.mkdir_p(File.dirname(metadata_path))
      File.write(metadata_path, default_metadata.merge(metadata).to_yaml)

      yield FITNESS.run(root: root, metadata_path: metadata_path)
    end
  end

  def default_metadata
    {
      "docker_boundaries" => [ "app/executors/" ],
      "fitness_self_referential" => [],
      "sensitive_field_names" => %w[secret_value private_key api_key],
      "user_intent_columns" => [],
      "critical_mutations" => [],
      "waivers" => []
    }
  end

  def result_for(results, id) = results.find { |result| result.id == id }

  describe "the report" do
    it "reports all ten functions individually" do
      in_repository({}) do |results|
        expect(results.map(&:id)).to eq(%w[AF-01 AF-02 AF-03 AF-04 AF-05 AF-06 AF-07 AF-08 AF-09 AF-10])
        expect(results.map(&:rule)).to all(be_a(String))
      end
    end

    it "reports a duration per function, so a slow one is visible" do
      in_repository({}) { |results| expect(results.map(&:duration_ms)).to all(be_a(Integer)) }
    end
  end

  describe "AF-01 — controllers do not import a Docker client" do
    it "detects the violation" do
      in_repository({ "app/controllers/services_controller.rb" => <<~RUBY }) do |results|
        class ServicesController < ApplicationController
          def show
            Docker::Service.get(params[:id])
          end
        end
      RUBY
        expect(result_for(results, "AF-01").status).to eq("fail")
        expect(result_for(results, "AF-01").violations.first.detail).to match(/Docker Engine API/)
      end
    end

    it "accepts a controller that records intent instead" do
      in_repository({ "app/controllers/services_controller.rb" => <<~RUBY }) do |results|
        class ServicesController < ApplicationController
          def update
            ScaleService.call(service_id: params[:id], replicas: params[:replicas])
          end
        end
      RUBY
        expect(result_for(results, "AF-01").status).to eq("pass")
      end
    end
  end

  describe "AF-02 — only the executor touches Docker" do
    it "detects a Docker reference outside app/executors/" do
      in_repository({ "app/jobs/deploy_job.rb" => "Excon.new('unix:///var/run/docker.sock')\n" }) do |results|
        expect(result_for(results, "AF-02").status).to eq("fail")
      end
    end

    it "detects a socket path in a library file" do
      in_repository({ "lib/opanel/sneaky.rb" => "SOCKET = '/var/run/docker.sock'\n" }) do |results|
        expect(result_for(results, "AF-02").status).to eq("fail")
      end
    end

    it "allows it inside the executor boundary" do
      in_repository({ "app/executors/swarm_executor.rb" => "SOCKET = '/var/run/docker.sock'\n" }) do |results|
        expect(result_for(results, "AF-02").status).to eq("pass")
      end
    end

    it "does not fire on a comment mentioning docker.sock" do
      in_repository({ "app/jobs/deploy_job.rb" => "# never open /var/run/docker.sock from here\n" }) do |results|
        expect(result_for(results, "AF-02").status).to eq("pass")
      end
    end
  end

  describe "AF-03 — reconcilers do not write user intent" do
    let(:metadata) do
      { "user_intent_columns" => [ { "table" => "services", "columns" => %w[desired_replicas] } ] }
    end

    it "detects a reconciler writing an intent column" do
      files = { "app/reconcilers/service_reconciler.rb" => <<~RUBY }
        class ServiceReconciler
          def converge(service, actual)
            service.update!(desired_replicas: actual.running_count)
          end
        end
      RUBY

      in_repository(files, metadata: metadata) do |results|
        expect(result_for(results, "AF-03").status).to eq("fail")
        expect(result_for(results, "AF-03").violations.first.detail).to match(/desired_replicas/)
      end
    end

    it "accepts a reconciler writing observation columns" do
      files = { "app/reconcilers/service_reconciler.rb" => <<~RUBY }
        class ServiceReconciler
          def converge(service, actual)
            service.update!(applied_revision: actual.revision, last_observed_at: Time.current)
          end
        end
      RUBY

      in_repository(files, metadata: metadata) do |results|
        expect(result_for(results, "AF-03").status).to eq("pass")
      end
    end
  end

  describe "AF-04 — the React tree imports no server-only code" do
    it "detects a Node built-in import" do
      in_repository({ "app/frontend/lib/bad.ts" => "import { readFileSync } from 'node:fs';\n" }) do |results|
        expect(result_for(results, "AF-04").status).to eq("fail")
      end
    end

    it "detects a database driver import" do
      in_repository({ "app/frontend/lib/bad.ts" => "import pg from 'pg';\n" }) do |results|
        expect(result_for(results, "AF-04").status).to eq("fail")
      end
    end

    it "accepts an import from inside the frontend tree" do
      in_repository({ "app/frontend/lib/good.ts" => "import { cn } from '@/lib/utils';\n" }) do |results|
        expect(result_for(results, "AF-04").status).to eq("pass")
      end
    end
  end

  describe "AF-05 — MCP goes through the Application Layer" do
    it "detects the adapter reaching the executor" do
      in_repository({ "app/mcp/service_tool.rb" => "SwarmExecutor.new.scale(service_id, 3)\n" }) do |results|
        expect(result_for(results, "AF-05").status).to eq("fail")
      end
    end

    it "accepts the adapter calling a Command" do
      in_repository({ "app/mcp/service_tool.rb" => "ScaleService.call(service_id:, replicas:)\n" }) do |results|
        expect(result_for(results, "AF-05").status).to eq("pass")
      end
    end
  end

  describe "AF-06 — no secret plaintext in output" do
    it "detects a sensitive field reaching a serializer" do
      in_repository({ "app/serializers/secret_serializer.rb" => <<~RUBY }) do |results|
        class SecretSerializer
          def as_json = { name: @secret.name, secret_value: @secret.secret_value }
        end
      RUBY
        expect(result_for(results, "AF-06").status).to eq("fail")
      end
    end

    it "detects one reaching an audit payload" do
      in_repository({ "app/audit/audit_event.rb" => "payload = { actor_id:, api_key: token }\n" }) do |results|
        expect(result_for(results, "AF-06").status).to eq("fail")
      end
    end

    it "accepts a serializer emitting a version reference" do
      in_repository({ "app/serializers/secret_serializer.rb" => <<~RUBY }) do |results|
        class SecretSerializer
          def as_json = { name: @secret.name, secret_version_id: @secret.current_version_id }
        end
      RUBY
        expect(result_for(results, "AF-06").status).to eq("pass")
      end
    end

    it "accepts a line that redacts the value" do
      in_repository({ "app/jobs/audit_job.rb" => "payload[:api_key] = REDACTED\n" }) do |results|
        expect(result_for(results, "AF-06").status).to eq("pass")
      end
    end
  end

  describe "AF-07 — critical mutations have a Policy" do
    let(:metadata) do
      { "critical_mutations" => [ { "command" => "DeleteService", "policy" => "ServicePolicy", "action" => "destroy?" } ] }
    end

    it "detects a declared mutation with no policy" do
      in_repository({}, metadata: metadata) do |results|
        expect(result_for(results, "AF-07").status).to eq("fail")
        expect(result_for(results, "AF-07").violations.first.detail).to match(/DeleteService/)
      end
    end

    it "detects a policy that exists but lacks the action" do
      files = { "app/policies/service_policy.rb" => "class ServicePolicy\n  def create? = true\nend\n" }

      in_repository(files, metadata: metadata) do |results|
        expect(result_for(results, "AF-07").status).to eq("fail")
      end
    end

    it "accepts a policy with the action" do
      files = { "app/policies/service_policy.rb" => "class ServicePolicy\n  def destroy? = owner?\nend\n" }

      in_repository(files, metadata: metadata) do |results|
        expect(result_for(results, "AF-07").status).to eq("pass")
      end
    end
  end

  describe "AF-08 — events and operations carry correlation" do
    it "detects an Operation with no correlation identifier" do
      in_repository({ "app/operations/scale_operation.rb" => <<~RUBY }) do |results|
        class ScaleOperation
          def call(service_id:, replicas:)
            enqueue(service_id, replicas)
          end
        end
      RUBY
        expect(result_for(results, "AF-08").status).to eq("fail")
      end
    end

    it "accepts one that carries it" do
      in_repository({ "app/operations/scale_operation.rb" => <<~RUBY }) do |results|
        class ScaleOperation
          def call(service_id:, replicas:, correlation_id:, operation_id:)
            enqueue(service_id, replicas, correlation_id, operation_id)
          end
        end
      RUBY
        expect(result_for(results, "AF-08").status).to eq("pass")
      end
    end
  end

  describe "AF-09 — destructive migrations are contract phase" do
    it "detects a column removal with no contract marker" do
      files = { "db/migrate/20260101000000_drop_it.rb" => <<~RUBY }
        class DropIt < ActiveRecord::Migration[8.1]
          def change
            remove_column :services, :legacy_flag, :boolean
          end
        end
      RUBY

      in_repository(files) { |results| expect(result_for(results, "AF-09").status).to eq("fail") }
    end

    it "accepts one that declares the phase and the decision" do
      files = { "db/migrate/20260101000000_drop_it.rb" => <<~RUBY }
        # migration-phase: contract
        # migration-contract-ref: ADR-0009
        class DropIt < ActiveRecord::Migration[8.1]
          def change
            remove_column :services, :legacy_flag, :boolean
          end
        end
      RUBY

      in_repository(files) { |results| expect(result_for(results, "AF-09").status).to eq("pass") }
    end
  end

  describe "AF-10 — a feature does not duplicate a primitive" do
    let(:primitive) { { "app/frontend/components/ui/badge/badge.tsx" => "export function Badge() {}\n" } }

    it "detects a feature component reimplementing one" do
      files = primitive.merge(
        "app/frontend/components/features/deploy/Badge.tsx" => "export function Badge() {}\n"
      )

      in_repository(files ) do |results|
        expect(result_for(results, "AF-10").status).to eq("fail")
        expect(result_for(results, "AF-10").violations.first.detail).to match(/duplicates the `badge`/)
      end
    end

    it "accepts a feature component with its own responsibility" do
      files = primitive.merge(
        "app/frontend/components/features/deploy/RolloutTimeline.tsx" => "export function RolloutTimeline() {}\n"
      )

      in_repository(files) { |results| expect(result_for(results, "AF-10").status).to eq("pass") }
    end
  end

  describe "waivers" do
    def waiver(**overrides)
      {
        "id" => "af-10-001", "function" => "AF-10", "finding" => "features/deploy/Badge",
        "reason" => "animates between states", "owner" => "douglas",
        "removal_story" => "M02-07", "expires_at" => (Date.today + 30).to_s
      }.merge(overrides.transform_keys(&:to_s))
    end

    it "silences a violation while it is in date" do
      files = {
        "app/frontend/components/ui/badge/badge.tsx" => "export function Badge() {}\n",
        "app/frontend/components/features/deploy/Badge.tsx" => "export function Badge() {}\n"
      }

      in_repository(files, metadata: { "waivers" => [ waiver ] } ) do |results|
        expect(result_for(results, "AF-10").status).to eq("pass")
        expect(result_for(results, "AF-10").waived).to eq(1)
      end
    end

    it "blocks again once it has expired, on a controlled clock" do
      files = {
        "app/frontend/components/ui/badge/badge.tsx" => "export function Badge() {}\n",
        "app/frontend/components/features/deploy/Badge.tsx" => "export function Badge() {}\n"
      }

      Dir.mktmpdir do |root|
        files.each do |path, content|
          full = File.join(root, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, content)
        end
        metadata_path = File.join(root, "fitness.yml")
        File.write(metadata_path, default_metadata.merge("waivers" => [ waiver("expires_at" => "2026-10-01") ]).to_yaml)

        in_date = FITNESS.run(root: root, metadata_path: metadata_path, on: Date.parse("2026-09-30"))
        expired = FITNESS.run(root: root, metadata_path: metadata_path, on: Date.parse("2026-10-02"))

        expect(result_for(in_date, "AF-10").status).to eq("pass")
        expect(result_for(expired, "AF-10").status).to eq("fail")
      end
    end

    %w[id function finding reason owner removal_story expires_at].each do |field|
      it "refuses a waiver with no #{field}" do
        expect { FITNESS.validate_waiver!(waiver(field.to_sym => "")) }
          .to raise_error(FITNESS::InvalidWaiver, /#{field}/)
      end
    end

    it "refuses a waiver with no deadline, which would be a permanent exception" do
      expect { FITNESS.validate_waiver!(waiver(expires_at: "")) }
        .to raise_error(FITNESS::InvalidWaiver, /permanent exception/)
    end

    %w[AF-02 AF-06 AF-07].each do |function|
      it "refuses to let an agent waive #{function} without recorded human approval" do
        expect { FITNESS.validate_waiver!(waiver(function: function, finding: "x")) }
          .to raise_error(FITNESS::InvalidWaiver, /human approval/)
      end

      it "accepts a #{function} waiver that records who approved it" do
        expect {
          FITNESS.validate_waiver!(waiver(function: function, finding: "x", approved_by: "douglas"))
        }.not_to raise_error
      end
    end
  end

  describe "this repository" do
    it "passes every function" do
      results = FITNESS.run(root: File.expand_path("../..", __dir__))

      failing = results.reject(&:passed?)
      expect(failing).to be_empty,
        "failing: #{failing.map { |result| "#{result.id}: #{result.violations.map(&:file).join(', ')}" }.join('; ')}"
    end
  end
end
