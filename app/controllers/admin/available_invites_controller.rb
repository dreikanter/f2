class Admin::AvailableInvitesController < ApplicationController
  def update
    user = User.find(params[:user_id])
    authorize user

    if user.update(available_invites_params)
      redirect_to admin_user_path(user), notice: "Available invites updated successfully."
    else
      redirect_to admin_user_path(user), alert: "Failed to update available invites."
    end
  end

  private

  def available_invites_params
    params.require(:user).permit(:available_invites)
  end
end
