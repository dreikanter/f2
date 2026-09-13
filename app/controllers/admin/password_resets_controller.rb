class Admin::PasswordResetsController < ApplicationController
  def create
    user = User.find(params[:user_id])
    authorize user, :update?

    if user.email_deactivated?
      redirect_to admin_user_path(user), alert: "Cannot send password reset email. Previous emails to this address were bounced by the mail server."
    else
      PasswordsMailer.deliver_to(:reset, user)
      redirect_to admin_user_path(user), notice: "Password reset email sent to #{user.email_address}."
    end
  end
end
