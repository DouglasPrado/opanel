# One Project, with what the actor may do to it (doc 09 §23, minimal version).
#
# ## What "minimal" means here, and what it will grow into
#
# doc 09 §23 defines `ProjectOverview` as *"Project + Environments + health
# agregado + último deployment"*. Three of those four do not exist yet:
# Environments arrive with `M01-11`, deployments with `M01-12`..`M01-18`, and
# derived health with `M01-19`. The Story asks for the minimal version, and the
# minimal version is the Project plus the one composition that is real today.
#
# ## Why it is not a wrapper around `Project`
#
# It answers two questions at once, and a screen needs both: *which* Project, and
# *what may this actor do with it*. Without that second half the page either
# offers actions the server will refuse — which teaches the operator that the UI
# lies — or asks the Policy once per button. The decisions come from the same
# `ProjectPolicy` the Commands go through, so what the UI shows and what the
# server enforces cannot disagree.
#
# The permissions are advisory. The server denies independently, on every
# mutation, and nothing here is an authorization.
class ProjectOverview
  Permissions = Data.define(:update, :archive)

  Result = Data.define(:id, :name, :slug, :description, :status, :created_at, :updated_at,
    :team, :permissions)

  TeamRef = Data.define(:id, :name, :slug)

  def self.call(actor:, project:)
    new(actor: actor, project: project).call
  end

  def initialize(actor:, project:)
    @actor = actor
    @project = project
  end

  def call
    policy = ProjectPolicy.new(actor, project)

    Result.new(
      id: project.external_id,
      name: project.name,
      slug: project.slug,
      description: project.description,
      status: project.status,
      created_at: project.created_at,
      updated_at: project.updated_at,
      team: TeamRef.new(id: project.team.external_id, name: project.team.name,
        slug: project.team.slug),
      # Read through the Policy rather than from the role, so a change to the
      # matrix of doc 04 §6.2 reaches the interface without anybody editing this.
      permissions: Permissions.new(update: policy.update?, archive: policy.archive?)
    )
  end

  private

  attr_reader :actor, :project
end
