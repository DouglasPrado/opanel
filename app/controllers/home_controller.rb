# Placeholder entry point for the Control Plane.
#
# It exists so that M00-01 can prove the application is not API-only and renders
# HTML. M00-04 replaces the rendered body with an Inertia page; the route and the
# controller stay.
class HomeController < ApplicationController
  def show
  end
end
