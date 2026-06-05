class Feeds::RefreshesController < ApplicationController
  def create
    @feed = Current.user.feeds.find(params[:feed_id])
    authorize @feed, :refresh?

    FeedRefreshJob.perform_later(@feed.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to feed_path(@feed), notice: "Feed refresh started" }
    end
  end
end
