class Settings::EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = find_user_by_token
    update_user_email(user)
    redirect_with_success
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_with_invalid_token
  rescue ActiveRecord::RecordInvalid
    redirect_with_failure
  end

  private

  def find_user_by_token
    User.find_by_token_for!(:change_email_confirmation, params[:token])
  end

  def update_user_email(user)
    target_email = user.unconfirmed_email&.strip&.downcase
    user.update!(email_address: target_email, unconfirmed_email: nil)
  end

  def redirect_with_success
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, notice: "Email address successfully updated."
  end

  def redirect_with_failure
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, alert: "Email confirmation failed. Please request a new confirmation link."
  end

  def redirect_with_invalid_token
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, alert: "Email confirmation link is invalid or has expired."
  end
end
