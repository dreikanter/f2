class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = find_user_by_token

    if account_confirmation?
      activate_user(user)
      redirect_with_account_activated
    elsif valid_email_change?
      update_user_email(user)
      redirect_with_email_updated
    else
      redirect_with_failure
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_with_invalid_token
  end

  private

  def find_user_by_token
    User.find_by_token_for!(:email_confirmation, params[:token])
  end

  def new_email
    params[:new_email]
  end

  def account_confirmation?
    new_email.blank?
  end

  def valid_email_change?
    new_email.present? && !email_already_taken?
  end

  def email_already_taken?
    User.exists?(email_address: new_email)
  end

  def activate_user(user)
    user.update!(state: :active) if user.inactive?
  end

  def update_user_email(user)
    user.update!(email_address: new_email)
  end

  def redirect_with_account_activated
    redirect_to new_session_path, notice: "Your email is now confirmed and the account is activated. Please sign in."
  end

  def redirect_with_email_updated
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, notice: "Email address successfully updated to #{new_email}."
  end

  def redirect_with_failure
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, alert: "Email confirmation failed. The email may already be taken."
  end

  def redirect_with_invalid_token
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, alert: "Email confirmation link is invalid or has expired."
  end
end
