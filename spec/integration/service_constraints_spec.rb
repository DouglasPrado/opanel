require "rails_helper"

# The constraints of doc 09 §18, proved against real PostgreSQL by the negative case.
#
# Every example here bypasses the model where possible, so what is being tested is
# the database and not the Ruby validation sitting in front of it.
RSpec.describe "service constraints", :integration do
  before(:each) do
    FactoryBot.rewind_sequences
    User.delete_all
  end

  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }

  describe "UNIQUE(environment_id, slug) WHERE deleted_at IS NULL (AC2)" do
    it "refuses a second living Service with the same slug in the same Environment" do
      create(:service, environment: environment, slug: "api")

      expect {
        Service.insert_all!([ {
          id: Opanel::Identifier.generate, environment_id: environment.id, team_id: team.id,
          name: "API again", slug: "api",
          service_type: "WEB", image_ref: "nginx:latest", replicas: 1,
          status: "DRAFT", technical_name: "test-api",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_services_unique_slug_per_environment_when_not_deleted/)
    end

    it "allows the slug of a deleted Service to be taken again" do
      create(:service, :deleted, environment: environment, slug: "api")

      expect { create(:service, environment: environment, slug: "api") }
        .to change(Service, :count).by(1)
    end

    # Extension: two Environments may have Services with the same slug.
    it "allows the same slug in a different Environment" do
      other_env = create(:environment, project: project)
      create(:service, environment: environment, slug: "api")

      expect { create(:service, environment: other_env, slug: "api") }
        .to change(Service, :count).by(1)
    end
  end

  describe "the CHECK constraints" do
    def insert(**attributes)
      Service.insert_all!([ {
        id: Opanel::Identifier.generate, environment_id: environment.id, team_id: team.id,
        name: "Test", slug: "test", service_type: "WEB",
        image_ref: "nginx:latest", replicas: 1, status: "DRAFT",
        technical_name: "test-service", created_at: Time.current, updated_at: Time.current
      }.merge(attributes) ])
    end

    it "refuses an id that is not a ULID" do
      expect { insert(id: "not-a-ulid") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_id_is_ulid/)
    end

    it "refuses a blank name" do
      expect { insert(name: "   ") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_name_present/)
    end

    it "refuses a name past 120 characters" do
      expect { insert(name: "a" * 121) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_name_present/)
    end

    it "refuses a slug that is not a URL segment" do
      expect { insert(slug: "Test Svc") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_slug_format/)
    end

    it "refuses a slug shorter than 2 characters" do
      expect { insert(slug: "s") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_slug_format/)
    end

    it "refuses a service_type outside the documented list" do
      expect { insert(service_type: "LAMBDA") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_type_is_known/)
    end

    it "accepts the documented service types" do
      %w[WEB WORKER CRON TASK DATABASE CACHE].each_with_index do |type, index|
        expect { insert(service_type: type, slug: "svc-#{index}") }.not_to raise_error
      end
    end

    it "refuses an empty image_ref" do
      expect { insert(image_ref: "   ") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_image_ref_present/)
    end

    it "refuses zero replicas" do
      expect { insert(replicas: 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_replicas_positive/)
    end

    it "refuses negative replicas" do
      expect { insert(replicas: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_replicas_positive/)
    end

    it "accepts positive replicas" do
      expect { insert(replicas: 5) }.not_to raise_error
    end

    it "refuses a status outside the documented list" do
      expect { insert(status: "WAITING") }
        .to raise_error(ActiveRecord::StatementInvalid, /services_status_is_known/)
    end

    it "accepts the documented statuses" do
      %w[DRAFT PROVISIONING RUNNING DEGRADED STOPPED DELETING].each_with_index do |status, index|
        expect { insert(status: status, slug: "svc-#{index}") }.not_to raise_error
      end
    end

    # Resource constraint checks.
    it "refuses cpu_limit < cpu_reservation" do
      expect { insert(cpu_reservation: 200, cpu_limit: 100) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_cpu_limit_gte_reservation/)
    end

    it "allows cpu_limit = cpu_reservation" do
      expect { insert(cpu_reservation: 100, cpu_limit: 100) }.not_to raise_error
    end

    it "allows cpu_limit > cpu_reservation" do
      expect { insert(cpu_reservation: 100, cpu_limit: 200) }.not_to raise_error
    end

    it "allows cpu_reservation without cpu_limit" do
      expect { insert(cpu_reservation: 100, cpu_limit: nil) }.not_to raise_error
    end

    it "allows cpu_limit without cpu_reservation" do
      expect { insert(cpu_reservation: nil, cpu_limit: 100) }.not_to raise_error
    end

    it "refuses memory_limit < memory_reservation" do
      expect { insert(memory_reservation: 512, memory_limit: 256) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_memory_limit_gte_reservation/)
    end

    it "allows memory_limit >= memory_reservation" do
      expect { insert(memory_reservation: 256, memory_limit: 512) }.not_to raise_error
    end

    # Revision constraints.
    it "refuses applied_revision > desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 6) }
        .to raise_error(ActiveRecord::StatementInvalid, /services_applied_revision_not_ahead/)
    end

    it "allows applied_revision = desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 5) }.not_to raise_error
    end

    it "allows applied_revision < desired_revision" do
      expect { insert(desired_revision: 5, applied_revision: 3) }.not_to raise_error
    end

    it "allows applied_revision = nil" do
      expect { insert(desired_revision: 1, applied_revision: nil) }.not_to raise_error
    end
  end

  describe "the foreign keys" do
    it "refuses a Service whose Environment does not exist" do
      expect {
        Service.insert_all!([ {
          id: Opanel::Identifier.generate, environment_id: Opanel::Identifier.generate,
          team_id: team.id, name: "Test", slug: "test",
          service_type: "WEB", image_ref: "nginx:latest", replicas: 1,
          status: "DRAFT", technical_name: "test",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "refuses a Service whose Team does not exist" do
      expect {
        Service.insert_all!([ {
          id: Opanel::Identifier.generate, environment_id: environment.id,
          team_id: Opanel::Identifier.generate, name: "Test", slug: "test",
          service_type: "WEB", image_ref: "nginx:latest", replicas: 1,
          status: "DRAFT", technical_name: "test",
          created_at: Time.current, updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
