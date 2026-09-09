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

  # Visual inspection of the imported component library (M00-05). Development
  # only: it is a tool for building the product, not part of it.
  get "gallery" => "gallery#show", as: :gallery if Rails.env.development? || Rails.env.test?
end
