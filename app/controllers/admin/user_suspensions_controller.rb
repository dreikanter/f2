class Admin::UserSuspensionsController < ApplicationController
  def create
    user = User.find(params[:user_id])
    authorize user

    deactivated_feeds = []

    User.transaction do
      user.suspend!
      user.sessions.destroy_all

      deactivated_feeds = user.feeds.enabled.pluck(:id, :name)
      user.feeds.enabled.update_all(state: :disabled)

      Event.create!(
        type: "UserSuspended",
        user: Current.user,
        subject: user,
        level: :warning,
        metadata: { deactivated_feed_ids: deactivated_feeds.map(&:first) }
      )
    end

    redirect_to admin_user_path(user), notice: "User has been suspended."
  end

  def destroy
    user = User.find(params[:user_id])
    authorize user

    User.transaction do
      user.unsuspend!

      Event.create!(
        type: "UserUnsuspended",
        user: Current.user,
        subject: user,
        level: :info
      )
    end

    redirect_to admin_user_path(user), notice: "User has been unsuspended."
  end
end
