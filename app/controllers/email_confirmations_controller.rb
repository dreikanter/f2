class EmailConfirmationsController < ApplicationController
  def show
    @user = User.find_by_token_for!(:email_change, params[:token])
    new_email = params[:new_email]

    if new_email.present? && !User.exists?(email_address: new_email)
      @user.update!(email_address: new_email)
      redirect_to profile_path, notice: "Email address successfully updated to #{new_email}."
    else
      redirect_to profile_path, alert: "Email confirmation failed. The email may already be taken."
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to profile_path, alert: "Email confirmation link is invalid or has expired."
  end
end
