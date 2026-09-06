Rails.application.routes.draw do
  # Health and readiness of the Control Plane itself. M00-15 replaces the Rails
  # default with an endpoint that also reports PostgreSQL and queue readiness.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
end
