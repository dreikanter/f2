class Admin::UserSuspensionsController < ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user
    @user.suspend!
    redirect_to admin_user_path(@user), notice: "User has been suspended."
  end

  def destroy
    @user = User.find(params[:user_id])
    authorize @user
    @user.unsuspend!
    redirect_to admin_user_path(@user), notice: "User has been unsuspended."
  end
end
