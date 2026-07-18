class PasswordsController < ApplicationController
  layout "modal"

  allow_unauthenticated_access
  before_action :find_user_by_token, only: [:edit, :update]

  def create
    if (user = User.find_by(email_address: params[:email_address], state: :active)) && !user.email_deactivated?
      PasswordsMailer.reset(user).deliver_later
      Event.create!(type: "mail.passwords_mailer.reset", user: user, subject: user, level: :info)
    end

    redirect_to new_session_path, notice: "If an active account exists for this email, you'll receive password reset instructions shortly."
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      redirect_to new_session_path, success: "Password reset."
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def find_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
  end
end
