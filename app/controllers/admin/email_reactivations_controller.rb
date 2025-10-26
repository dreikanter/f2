class Admin::EmailReactivationsController < ApplicationController
  def create
    @user = User.find(params[:user_id])
    authorize @user, :reactivate_email?
    @user.reactivate_email!
    redirect_to admin_user_path(@user), notice: "Email reactivated successfully."
  end
end
