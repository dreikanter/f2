class FeedsController < ApplicationController

  def index
    @feeds = user_feeds.order(:name)
  end

  def new
    @feed = user_feeds.build
  end

  def show
    @feed = load_feed
  end

  def edit
    @feed = load_feed
  end

  def create
    @feed = user_feeds.build(feed_params)

    if @feed.save
      notice_message = "Feed was successfully created."
      if @feed.access_token&.active?
        notice_message += " You can now enable it to start processing items."
      end
      redirect_to @feed, notice: notice_message
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @feed = load_feed

    if @feed.update(feed_params)
      redirect_to @feed, notice: "Feed was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @feed = load_feed
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

  def user_feeds
    Current.user.feeds
  end

  def load_feed
    user_feeds.find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(
      :name,
      :url,
      :cron_expression,
      :loader,
      :processor,
      :normalizer,
      :import_after,
      :description,
      :access_token_id,
      :state
    )
  end
end
