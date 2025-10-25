class Registration::EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = find_user_by_token
    activate_user(user)
    redirect_to new_session_path, notice: "Your email is now confirmed and the account is activated. Please sign in."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_session_path, alert: "Email confirmation link is invalid or has expired."
  end

  private

  def find_user_by_token
    User.find_by_token_for!(:initial_email_confirmation, params[:token])
  end

  def activate_user(user)
    user.update!(state: :active) if user.inactive?
  end
end
