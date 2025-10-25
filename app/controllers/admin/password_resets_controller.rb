class Admin::PasswordResetsController < ApplicationController
  def show
    @user = load_user
    authorize @user, :update?
  end

  def create
    user = load_user
    authorize user, :update?
    PasswordsMailer.reset(user).deliver_later unless user.email_deactivated?
    redirect_to admin_user_path(user), notice: "Password reset email sent to #{user.email_address}."
  end

  private

  def load_user
    User.find(params[:user_id])
  end
end
