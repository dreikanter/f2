class Feeds::PurgesController < ApplicationController
  def create
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :purge?

    started = feed.with_lock do
      next false if feed.purging?

      result = Feed::StateTransition.new(feed).disable
      raise ActiveRecord::RecordInvalid, feed unless result.success?

      WithdrawAllPostsJob.perform_later(feed.id, Current.user.id) || raise(ActiveJob::EnqueueError, "Could not enqueue feed purge")
      true
    end

    if started
      redirect_to feed_path(feed), notice: "Feed purge started for #{feed.target_group}"
    else
      redirect_to feed_path(feed), alert: "Feed purge is already in progress."
    end
  end
end
