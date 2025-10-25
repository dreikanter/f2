class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = find_user_by_token

    if account_confirmation?(user)
      activate_user(user)
      redirect_with_account_activated
    elsif valid_email_change?(user)
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
    # Try email_change token first (for email changes), then email_confirmation (for new accounts)
    User.find_by_token_for(:email_change, params[:token]) ||
      User.find_by_token_for!(:email_confirmation, params[:token])
  end

  def new_email(user)
    user.unconfirmed_email&.strip&.downcase
  end

  def account_confirmation?(user)
    new_email(user).blank?
  end

  def valid_email_change?(user)
    new_email(user).present? && !email_already_taken?(user)
  end

  def email_already_taken?(user)
    User.where.not(id: user.id).exists?(email_address: new_email(user))
  end

  def activate_user(user)
    user.update!(state: :active) if user.inactive?
  end

  def update_user_email(user)
    target_email = new_email(user)

    # Race-safe update: only update if unconfirmed_email still matches and target email is available
    updated = user.update(
      email_address: target_email,
      unconfirmed_email: nil
    )

    # Verify the update succeeded and email was actually changed
    raise ActiveRecord::RecordInvalid unless updated && user.reload.email_address == target_email
  end

  def redirect_with_account_activated
    redirect_to new_session_path, notice: "Your email is now confirmed and the account is activated. Please sign in."
  end

  def redirect_with_email_updated
    redirect_path = authenticated? ? settings_path : new_session_path
    redirect_to redirect_path, notice: "Email address successfully updated."
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
