class FeedsController < ApplicationController
  include Authentication

  before_action :require_authentication
  before_action :set_feed, only: [:show, :edit, :update, :destroy]

  def index
    @feeds = user_feeds.order(:name)
  end

  def new
    @feed = user_feeds.build
  end

  def create
    @feed = user_feeds.build(feed_params)

    if @feed.save
      redirect_to @feed, notice: "Feed was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @feed.update(feed_params)
      redirect_to @feed, notice: "Feed was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

  def user_feeds
    Current.user.feeds
  end

  def set_feed
    @feed = user_feeds.find(params[:id])
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
      :description
    )
  end
end
