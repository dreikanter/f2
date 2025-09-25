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
    @feed = user_feeds.build(new_feed_params)
    @feed.state = :inactive
    @feed.generate_unique_name!

    if @feed.save
      redirect_to @feed, notice: "Feed was successfully created. Complete the configuration to enable it."
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

  def new_feed_params
    return {} unless params[:feed]

    params.require(:feed).permit(
      :name,
      :url,
      :feed_profile_id
    )
  end

  def feed_params
    return {} unless params[:feed]

    params.require(:feed).permit(
      :name,
      :url,
      :cron_expression,
      :feed_profile_id,
      :import_after,
      :description,
      :access_token_id,
      :target_group,
      :state
    )
  end
end
