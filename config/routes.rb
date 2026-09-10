Rails.application.routes.draw do
  # Health and readiness of the Control Plane itself. Rails' default only proves
  # the process booted; this one reports PostgreSQL and the queue separately,
  # because they fail separately.
  get "up" => "health#show", as: :rails_health_check

  root "home#show"

  # Authentication (M01-01). Served by Inertia; no REST endpoint exists to feed
  # these pages, and the public API of later Milestones will reuse the same
  # Commands rather than duplicating their rules.
  get "sign_up" => "registrations#new", as: :sign_up
  post "sign_up" => "registrations#create"
  get "sign_in" => "sessions#new", as: :sign_in
  post "sign_in" => "sessions#create"
  delete "sign_out" => "sessions#destroy", as: :sign_out

  # The user's own devices: list and revoke individually (doc 04 §8.2).
  resources :sessions, only: %i[index destroy], path: "settings/sessions", as: :account_sessions

  # The panel, addressed by Team slug (doc 10 §3.2). The slug is human and
  # mutable, so it is resolved to a Team inside the tenancy boundary on every
  # request rather than trusted from the path — a slug in the URL is an argument,
  # not an authorization.
  scope "t/:team_slug", as: :panel do
    # Projects (M01-07). `index` keeps the path the shell's navigation already
    # points at; the mutations are `POST`/`PATCH` on the same collection, so the
    # short flow of doc 10 §7.2 needs no second screen.
    get "projects", to: "projects#index", as: :projects
    post "projects", to: "projects#create"
    # UC-009 passo 6: depois de criar, a UI abre o Project Overview. The read is a
    # `GET` on the same member path the rename writes to.
    get "projects/:id", to: "projects#show", as: :project
    # No named helper: the scope's own `as: :panel` would become the whole name,
    # and `panel_path` for a Project rename is a name that means nothing. The GET
    # above owns `panel_project_path`, and nothing generates this one — the form
    # posts the path it is already on.
    patch "projects/:id", to: "projects#update", as: nil
    post "projects/:id/archive", to: "projects#archive", as: :archive_project
    # Environments (M01-11). Nested under Projects; list, create, show and update.
    get "projects/:project_id/environments", to: "environments#index", as: :project_environments
    post "projects/:project_id/environments", to: "environments#create"
    get "projects/:project_id/environments/:id", to: "environments#show", as: :project_environment
    patch "projects/:project_id/environments/:id", to: "environments#update"
    # Services (M01-12). Nested under Environments; list, create, show and update.
    get "projects/:project_id/environments/:environment_id/services", to: "services#index",
as: :project_environment_services
    post "projects/:project_id/environments/:environment_id/services", to: "services#create"
    get "projects/:project_id/environments/:environment_id/services/:id", to: "services#show",
as: :project_environment_service
    patch "projects/:project_id/environments/:environment_id/services/:id", to: "services#update"
    # Clusters (M01-08). `preflight` is a GET because it reads the machine and
    # the daemon and changes nothing; `refresh` is a POST because it writes the
    # observation it took.
    get "clusters", to: "clusters#index", as: :clusters
    get "clusters/preflight", to: "clusters#preflight", as: :cluster_preflight
    post "clusters", to: "clusters#create"
    post "clusters/:id/refresh", to: "clusters#refresh", as: :refresh_cluster
    get "audit", to: "panel#audit", as: :audit
    get "settings", to: "panel#settings", as: :settings
  end

  # Teams (M01-02). Three actions only: the tenant is created here and read
  # here, and everything else about it — members, invitations, ownership
  # transfer — belongs to the Stories that own those concepts. Suspension has no
  # route in this Story on purpose; the Command exists and nothing web-facing
  # reaches it.
  resources :teams, only: %i[index create show]

  # Visual inspection of the imported component library (M00-05). Development
  # only: it is a tool for building the product, not part of it.
  get "gallery" => "gallery#show", as: :gallery if Rails.env.development? || Rails.env.test?
end
