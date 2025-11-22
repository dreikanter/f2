class Admin::SuspensionsController < ApplicationController
  def create
    authorize User, :suspend?
    user = find_user
    suspend_user_and_record_event(user)
    redirect_to admin_user_path(user), notice: "User has been suspended."
  end

  def destroy
    authorize User, :unsuspend?
    user = find_user
    unsuspend_user_and_record_event(user)
    redirect_to admin_user_path(user), notice: "User has been unsuspended."
  end

  private

  def find_user
    User.find(params[:user_id])
  end

  def suspend_user_and_record_event(user)
    User.transaction do
      user.suspend!
      user.sessions.destroy_all
      deactivated_feed_ids = deactivate_all_feeds(user)
      record_suspension_event(user, deactivated_feed_ids)
    end
  end

  def unsuspend_user_and_record_event(user)
    User.transaction do
      user.unsuspend!
      record_unsuspension_event(user)
    end
  end

  def deactivate_all_feeds(user)
    feed_ids = user.feeds.enabled.pluck(:id)
    user.feeds.enabled.update_all(state: :disabled)
    feed_ids
  end

  def record_suspension_event(user, deactivated_feed_ids)
    Event.create!(
      type: "user_suspended",
      user: Current.user,
      subject: user,
      level: :warning,
      metadata: { deactivated_feed_ids: deactivated_feed_ids }
    )
  end

  def record_unsuspension_event(user)
    Event.create!(
      type: "user_unsuspended",
      user: Current.user,
      subject: user,
      level: :info
    )
  end
end
