class Feeds::RefreshesController < ApplicationController
  THROTTLED_MESSAGE = "This feed was just refreshed. Give it a moment before refreshing again.".freeze

  rate_limit to: 10, within: 1.minute,
             by: -> { "#{Current.user.id}:#{params[:feed_id]}" },
             only: :create,
             with: :refresh_throttled

  def create
    @feed = Current.user.feeds.find(params[:feed_id])
    authorize @feed, :refresh?

    FeedRefreshJob.perform_later(@feed.id, manual: true)

    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = "Feed refresh started"
        render turbo_stream: turbo_stream.replace("flash-messages", partial: "layouts/flash")
      end
      format.html { redirect_to feed_path(@feed), notice: "Feed refresh started" }
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
