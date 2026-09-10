# The Clusters section of the panel, and the bootstrap screen of UC-003.
#
# Inherits `PanelController` for its `require_team`, which resolves the slug in
# the URL through the tenancy boundary on every request.
#
# ## The browser never speaks to Docker
#
# doc 06 §4.2 and AC8. Every Docker call happens in a worker process on the
# server, through `SwarmBootstrap`, and what reaches the page is the *result* —
# check names, statuses and details. There is no endpoint here that proxies the
# Engine, and there is no field on any page that carries an Engine address.
class ClustersController < PanelController
  include ErrorEnvelope

  INDEX_PAGE = "Panel/Clusters"

  def index
    render inertia: INDEX_PAGE, props: page_props
  end

  # UC-003 steps 1 and 2: run the checks and put the detected addresses in front
  # of the operator **before** anything is initialised. A `GET`, because it
  # changes nothing — the checks read the machine and the daemon.
  def preflight
    render inertia: INDEX_PAGE, props: page_props(preflight: run_preflight)
  end

  # UC-003 steps 3 and 4.
  def create
    result = BootstrapCluster.call(
      actor: current_user, team: team, name: submitted[:name], slug: submitted[:slug],
      advertise_address: submitted[:advertiseAddress], adopt_existing: adopt_existing?
    )

    if result.failure?
      return render inertia: INDEX_PAGE,
        props: page_props.merge(error: error_envelope(result), details: safe_details(result)),
        status: error_status(result)
    end

    redirect_to panel_clusters_path(team_slug: team.slug)
  end

  # Takes a fresh reading. A `POST` because it writes the observation, even though
  # it changes nothing an operator asked for.
  def refresh
    cluster = scoped_cluster
    raise ActiveRecord::RecordNotFound if cluster.nil?

    result = RefreshClusterStatus.call(actor: current_user, cluster: cluster)

    # The tenancy boundary above already answered 404 for anybody outside the
    # Team, so this path is reached only by a member. Honouring the Result anyway
    # rather than discarding it: a Command that refuses and a caller that
    # redirects as if it had not is how a refusal becomes invisible.
    if result.failure?
      return render inertia: INDEX_PAGE, props: page_props.merge(error: error_envelope(result)),
        status: error_status(result)
    end

    redirect_to panel_clusters_path(team_slug: team.slug)
  end

  private

  # Through the tenancy boundary, never by id with a check afterwards
  # (Annex C §7.3). A Cluster of another Team is answered as absent.
  def scoped_cluster
    id = Opanel::Identifier.parse(:cluster, params[:id])

    TenantScope.for(current_user, Cluster).relation.where(team_id: team.id).find_by(id: id)
  rescue Opanel::Identifier::InvalidIdentifier
    nil
  end

  def page_props(preflight: nil)
    clusters = TenantScope.for(current_user, Cluster).relation
      .where(team_id: team.id).order(:id).limit(PAGE_SIZE)

    {
      team: { id: team.external_id, name: team.name, slug: team.slug },
      clusters: clusters.map { |cluster| readiness_prop(cluster) },
      preflight: preflight,
      permissions: { bootstrap: ClusterPolicy.new(current_user, Cluster.new(team: team)).bootstrap? }
    }
  end

  PAGE_SIZE = 25

  def run_preflight
    report = Preflight.call

    {
      checks: report.checks.map { |check| { name: check.name, status: check.status, detail: check.detail } },
      # Only what the operator has to choose between. The full interface list
      # would put loopback on the screen as if it were an option.
      candidates: report.advertise_candidates.map { |i| { name: i.name, address: i.address, private: i.private? } },
      suggested: report.suggested_advertise_address,
      choiceRequired: report.advertise_address_required?,
      blocked: report.blocked?
    }
  end

  # Written out field by field: what leaves the server is a decision, and a list
  # nobody wrote is a list nobody reviewed. The Swarm id is here because it
  # identifies the runtime and is not a credential; the join token is neither a
  # column nor a prop anywhere (AC10).
  def readiness_prop(cluster)
    view = ClusterReadinessView.call(actor: current_user, cluster: cluster)

    {
      id: view.id,
      name: view.name,
      slug: view.slug,
      status: view.status,
      swarmId: view.swarm_id,
      advertiseAddress: view.advertise_address,
      observedAt: view.observed_at&.iso8601,
      stale: view.stale?,
      unreachableReason: view.unreachable_reason,
      operational: view.operational?,
      highlyAvailable: view.highly_available?,
      checks: view.checks.map { |check| { name: check.name, status: check.status, detail: check.detail } },
      permissions: { refresh: view.permissions.refresh }
    }
  end

  # The failure details a page may render. An allowlist rather than the whole
  # `details` hash: a Command is free to put anything in there, and a controller
  # that forwards it wholesale turns every future detail into a shared prop
  # nobody reviewed.
  def safe_details(result)
    details = result.details

    {
      failedChecks: details[:failed_checks],
      candidates: details[:candidates],
      cause: details[:cause],
      adoptable: details[:adoptable],
      swarmId: details[:swarm_id]
    }.compact
  end

  def adopt_existing? = ActiveModel::Type::Boolean.new.cast(submitted[:adoptExisting]).present?

  def submitted
    params.permit(:name, :slug, :advertiseAddress, :adoptExisting)
  end
end
