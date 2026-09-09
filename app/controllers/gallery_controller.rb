# Renders every imported component for visual inspection (M00-05).
#
# Development and test only. The route does not exist in production: a gallery is
# a tool for building the product, not a page of it.
class GalleryController < ApplicationController
  # The route only exists in development and test, and the page renders the
  # component library with no data behind it. Nothing here is worth a login.
  allow_unauthenticated_access

  def show
    render inertia: "Gallery"
  end
end
