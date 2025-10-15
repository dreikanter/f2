class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization
  include UserOnboarding

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def pundit_user
    Current.user
  end

  def user_not_authorized
    redirect_to root_path, alert: "Access denied. You don't have permission to perform this action."
  end
end
