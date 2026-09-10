# A single Environment with all its details (doc 09 §23).
#
# The minimal version for M01. Later Milestones will add deployment status,
# last release, configuration drift, etc.
class EnvironmentOverview
  Overview = Data.define(
    :id, :name, :slug, :type, :status, :project_id, :cluster_id,
    :auto_promote_secrets, :desired_revision, :applied_revision, :created_at
  )

  def self.call(actor:, environment:)
    new(actor: actor, environment: environment).call
  end

  def initialize(actor:, environment:)
    @actor = actor
    @environment = environment
  end

  def call
    Opanel::Authorization.authorize!(actor, :view, environment)

    Overview.new(
      id: environment.external_id,
      name: environment.name,
      slug: environment.slug,
      type: environment.type,
      status: environment.status,
      project_id: environment.project.external_id,
      cluster_id: environment.cluster.external_id,
      auto_promote_secrets: environment.auto_promote_secrets,
      desired_revision: environment.desired_revision,
      applied_revision: environment.applied_revision,
      created_at: environment.created_at
    )
  end

  private

  attr_reader :actor, :environment
end
