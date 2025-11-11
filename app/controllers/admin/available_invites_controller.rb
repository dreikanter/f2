class Admin::AvailableInvitesController < ApplicationController
  def update
    user = User.find(params[:user_id])
    authorize user

    if user.update(available_invites: available_invites)
      render turbo_stream: turbo_stream.replace(
        "available-invites-value",
        partial: "admin/users/available_invites_value",
        locals: { user: user }
      )
    else
      flash.now[:alert] = "Failed to update available invites."
      render turbo_stream: turbo_stream.replace(
        "flash-messages",
        partial: "layouts/flash"
      )
    end
  end

  private

  def available_invites
    Integer(available_invites_params[:available_invites])
  end

  def available_invites_params
    params.require(:user).permit(:available_invites)
  end
end
