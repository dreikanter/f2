class LandingController < ApplicationController
  allow_unauthenticated_access

  def index
    redirect_to status_path if authenticated?
  end
end
