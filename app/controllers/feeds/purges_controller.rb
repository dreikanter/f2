class Feeds::PurgesController < ApplicationController
  def show
    @feed = Current.user.feeds.find(params[:feed_id])
    authorize @feed, :purge?
  end

  def create
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :purge?

    GroupPurgeJob.perform_later(feed.id)

    Event.create!(
      type: "GroupPurgeStarted",
      user: Current.user,
      subject: feed,
      level: :info,
      metadata: { target_group: feed.target_group }
    )

    redirect_to feed_path(feed), notice: "Feed purge started for #{feed.target_group}"
  end
end
