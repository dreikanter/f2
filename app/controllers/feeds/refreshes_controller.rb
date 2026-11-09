class Feeds::RefreshesController < ApplicationController
  THROTTLED_MESSAGE = "This feed was just refreshed. Give it a moment before refreshing again.".freeze

  rate_limit to: 10, within: 1.minute,
             by: -> { "#{Current.user.id}:#{params[:feed_id]}" },
             only: :create,
             with: :refresh_throttled

  def create
    @feed = Current.user.feeds.find(params[:feed_id])
    authorize @feed, :refresh?

    refresh_status = Feed::RefreshStatus.new(feed: @feed, requested: true)
    FeedRefreshJob.perform_later(@feed.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            helpers.dom_id(@feed, :header),
            partial: "feeds/header",
            locals: { feed: @feed, refresh_status: refresh_status }
          ),
          turbo_stream.update("flash-messages", "")
        ]
      end
      format.html { redirect_to feed_path(@feed, refresh_after: refresh_status.cursor) }
    end
  end

  private

  def refresh_throttled
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = THROTTLED_MESSAGE
        render turbo_stream: turbo_stream.replace("flash-messages", partial: "layouts/flash"),
               status: :too_many_requests
      end
      format.html { redirect_to feed_path(params[:feed_id]), alert: THROTTLED_MESSAGE }
    end
  end
end
