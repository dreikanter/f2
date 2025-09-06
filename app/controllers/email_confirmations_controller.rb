class EmailConfirmationsController < ApplicationController
  def show
    user = find_user_by_token

    if valid_email_change?
      update_user_email(user)
      redirect_with_success
    else
      redirect_with_failure
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_with_invalid_token
  end

  private

  def find_user_by_token
    User.find_by_token_for!(:email_change, params[:token])
  end

  def new_email
    params[:new_email]
  end

  def valid_email_change?
    new_email.present? && !email_already_taken?
  end

  def email_already_taken?
    User.exists?(email_address: new_email)
  end

  def update_user_email(user)
    user.update!(email_address: new_email)
  end

  def redirect_with_success
    redirect_to profile_path, notice: "Email address successfully updated to #{new_email}."
  end

  def redirect_with_failure
    redirect_to profile_path, alert: "Email confirmation failed. The email may already be taken."
  end

  def redirect_with_invalid_token
    redirect_to profile_path, alert: "Email confirmation link is invalid or has expired."
  end
end
