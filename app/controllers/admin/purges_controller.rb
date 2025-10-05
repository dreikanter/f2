class Admin::PurgesController < ApplicationController
  def new
    authorize :purge, :create?
    @access_tokens = Current.user.access_tokens.active
  end

  def create
    authorize :purge, :create?

    access_token = Current.user.access_tokens.find(purge_params[:access_token_id])
    target_group = purge_params[:target_group]

    GroupPurgeJob.perform_later(access_token.id, target_group)

    Event.create!(
      type: "GroupPurgeStarted",
      user: Current.user,
      subject: access_token,
      level: :info,
      metadata: { target_group: target_group }
    )

    redirect_to new_admin_purge_path, notice: "Group withdrawal started for #{target_group}"
  end

  private

  def purge_params
    params.require(:purge).permit(:access_token_id, :target_group)
  end
end
