class Feeds::PurgesController < ApplicationController
  before_action :set_feed

  def show
    authorize @feed, :purge?
  end

  def create
    authorize @feed, :purge?

    GroupPurgeJob.perform_later(@feed.access_token.id, @feed.target_group)

    Event.create!(
      type: "GroupPurgeStarted",
      user: Current.user,
      subject: @feed,
      level: :info,
      metadata: { target_group: @feed.target_group }
    )

    redirect_to feed_path(@feed), notice: "Feed purge started for #{@feed.target_group}"
  end

  private

  def set_feed
    @feed = Current.user.feeds.find(params[:feed_id])
  end
end
