class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :redirect_to_onboarding

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def redirect_to_onboarding
    return unless session[:onboarding]
    return if controller_name == "onboardings"

    redirect_to onboarding_path
  end

  def pundit_user
    Current.user
  end

  def user_not_authorized
    redirect_to root_path, alert: "Access denied. You don't have permission to perform this action."
  end
end
