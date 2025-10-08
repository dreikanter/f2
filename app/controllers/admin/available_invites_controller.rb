class Admin::AvailableInvitesController < ApplicationController
  def update
    user = User.find(params[:user_id])
    authorize user

    available_invites = params.require(:user).fetch(:available_invites)
    user.update_column(:available_invites, available_invites)

    redirect_to admin_user_path(user), notice: "Available invites updated successfully."
  end
end
