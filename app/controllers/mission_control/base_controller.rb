module MissionControl
  class BaseController < ApplicationController
    before_action :authorize_admin

    private

    def authorize_admin
      authorize :admin, :show?
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      # Use hardcoded path to avoid Mission Control's default_url_options
      # injecting server_id parameter into our app's routes
      redirect_to "/session/new"
    end
  end
end
