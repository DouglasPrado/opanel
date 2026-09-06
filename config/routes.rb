Rails.application.routes.draw do
  # Health and readiness of the Control Plane itself. M00-15 replaces the Rails
  # default with an endpoint that also reports PostgreSQL and queue readiness.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"

  # Visual inspection of the imported component library (M00-05). Development
  # only: it is a tool for building the product, not part of it.
  get "gallery" => "gallery#show", as: :gallery if Rails.env.development? || Rails.env.test?
end
