class Feeds::PurgesController < ApplicationController
  def create
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :purge?

    WithdrawAllPostsJob.perform_later(feed.id)

    redirect_to feed_path(feed), notice: "Feed purge started for #{feed.target_group}"
  end
end
