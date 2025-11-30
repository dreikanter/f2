class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :current_user

  private

  # Pundit uses this method to get the "user" for authorization checks
  # SEE: https://github.com/varvet/pundit?tab=readme-ov-file#customize-pundit-user
  def current_user
    Current.user
  end

  def user_not_authorized
    redirect_to root_path, alert: "Access denied. You don't have permission to perform this action."
  end
end
