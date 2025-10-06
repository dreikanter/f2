class Admin::PasswordResetsController < ApplicationController
  def create
    authorize user, :update?
    PasswordsMailer.reset(user).deliver_later
    redirect_to admin_user_path(user), notice: "Password reset email sent to #{user.email_address}."
  end

  private

  def user
    @user ||= User.find(params[:user_id])
  end
end
