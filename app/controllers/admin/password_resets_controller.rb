class Admin::PasswordResetsController < ApplicationController
  def show
    @user = load_user
    authorize @user, :update?
  end

  def create
    user = load_user
    authorize user, :update?

    if user.email_deactivated?
      redirect_to admin_user_path(user), alert: "Cannot send password reset email. Previous emails to this address were bounced by the mail server."
    else
      PasswordsMailer.reset(user).deliver_later
      redirect_to admin_user_path(user), notice: "Password reset email sent to #{user.email_address}."
    end
  end

  private

  def load_user
    User.find(params[:user_id])
  end
end
