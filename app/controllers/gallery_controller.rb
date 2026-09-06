# Renders every imported component for visual inspection (M00-05).
#
# Development and test only. The route does not exist in production: a gallery is
# a tool for building the product, not a page of it.
class GalleryController < ApplicationController
  def show
    render inertia: "Gallery"
  end
end
