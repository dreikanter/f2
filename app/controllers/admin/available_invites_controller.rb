class Admin::AvailableInvitesController < ApplicationController
  def update
    user = User.find(params[:user_id])
    authorize user

    if user.update(available_invites: available_invites)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "available-invites-value",
            partial: "admin/users/available_invites_value",
            locals: { user: user }
          )
        end
        format.html { redirect_to admin_user_path(user), notice: "Available invites updated successfully." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash", partial: "shared/flash", locals: { alert: "Failed to update available invites." })
        end
        format.html { redirect_to admin_user_path(user), alert: "Failed to update available invites." }
      end
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
