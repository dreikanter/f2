class Admin::UserSuspensionsController < ApplicationController
  def create
    user = find_and_authorize_user
    suspend_user_and_record_event(user)
    redirect_to admin_user_path(user), notice: "User has been suspended."
  end

  def destroy
    user = find_and_authorize_user
    unsuspend_user_and_record_event(user)
    redirect_to admin_user_path(user), notice: "User has been unsuspended."
  end

  private

  def find_and_authorize_user
    User.find(params[:user_id]).tap { |user| authorize user }
  end

  def suspend_user_and_record_event(user)
    User.transaction do
      user.suspend!
      terminate_all_sessions(user)
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

  def terminate_all_sessions(user)
    user.sessions.destroy_all
  end

  def deactivate_all_feeds(user)
    feed_ids = user.feeds.enabled.pluck(:id)
    user.feeds.enabled.update_all(state: :disabled)
    feed_ids
  end

  def record_suspension_event(user, deactivated_feed_ids)
    Event.create!(
      type: "UserSuspended",
      user: Current.user,
      subject: user,
      level: :warning,
      metadata: { deactivated_feed_ids: deactivated_feed_ids }
    )
  end

  def record_unsuspension_event(user)
    Event.create!(
      type: "UserUnsuspended",
      user: Current.user,
      subject: user,
      level: :info
    )
  end
end
