class EmailConfirmationsController < ApplicationController
  def show
    user = find_user_by_token
    new_email = params[:new_email]

    if valid_email_change?(new_email)
      update_user_email(user, new_email)
      redirect_with_success(new_email)
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

  def valid_email_change?(new_email)
    new_email.present? && !email_already_taken?(new_email)
  end

  def email_already_taken?(email)
    User.exists?(email_address: email)
  end

  def update_user_email(user, new_email)
    user.update!(email_address: new_email)
  end

  def redirect_with_success(new_email)
    redirect_to profile_path, notice: "Email address successfully updated to #{new_email}."
  end

  def redirect_with_failure
    redirect_to profile_path, alert: "Email confirmation failed. The email may already be taken."
  end

  def redirect_with_invalid_token
    redirect_to profile_path, alert: "Email confirmation link is invalid or has expired."
  end
end
