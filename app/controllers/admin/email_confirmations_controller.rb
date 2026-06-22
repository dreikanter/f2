class Admin::EmailConfirmationsController < ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :confirm_email?
    @user.confirm_email!
    redirect_to admin_user_path(@user), success: "Email confirmed."
  end
end
