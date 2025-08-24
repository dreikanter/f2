class FeedsController < ApplicationController
  include Authentication

  before_action :require_authentication
  before_action :set_feed, only: [:show, :edit, :update, :destroy]

  def index
    @feeds = Current.user.feeds.order(:name)
  end

  def show
  end

  def new
    @feed = Current.user.feeds.build
  end

  def create
    @feed = Current.user.feeds.build(feed_params)

    if @feed.save
      redirect_to @feed, notice: "Feed was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @feed.update(feed_params)
      redirect_to @feed, notice: "Feed was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

  def set_feed
    @feed = Current.user.feeds.find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(:name, :url, :cron_expression, :loader, :processor, :normalizer, :import_after, :description)
  end
end
