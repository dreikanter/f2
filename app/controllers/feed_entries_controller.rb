class FeedEntriesController < ApplicationController
  def show
    @feed_entry = policy_scope(FeedEntry).preload(:feed, :posts).find(params[:id])
    authorize @feed_entry
  end
end
