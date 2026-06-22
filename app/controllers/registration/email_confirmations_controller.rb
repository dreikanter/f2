class Registration::EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = find_user_by_token
    user.confirm_email!
    redirect_to new_session_path, success: "Your email is now confirmed. Please sign in to get started."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_session_path, alert: "Email confirmation link is invalid or has expired."
  end

  private

  def find_user_by_token
    User.find_by_token_for!(:initial_email_confirmation, params[:token])
  end
end
