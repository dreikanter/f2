class PasswordsController < ApplicationController
  layout "tailwind"

  allow_unauthenticated_access
  before_action :find_user_by_token, only: [:edit, :update]

  def create
    if user = User.find_by(email_address: params[:email_address], state: :active)
      PasswordsMailer.reset(user).deliver_later unless user.email_deactivated?
    end

    redirect_to new_session_path, notice: "If an active account exists for this email, you'll receive password reset instructions shortly."
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
    end
  end

  private

  def find_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
  end
end
