class Feeds::RefreshesController < ApplicationController
  def create
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :refresh?

    FeedRefreshJob.perform_later(feed.id)

    redirect_to feed_path(feed), notice: "Feed refresh started"
  end
end
