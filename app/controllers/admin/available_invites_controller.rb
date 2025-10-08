class Admin::AvailableInvitesController < ApplicationController
  def update
    user = User.find(params[:user_id])
    authorize user

    if user.update(available_invites: params[:available_invites])
      redirect_to admin_user_path(user), notice: "Available invites updated successfully."
    else
      redirect_to admin_user_path(user), alert: "Failed to update available invites."
    end
  end
end
