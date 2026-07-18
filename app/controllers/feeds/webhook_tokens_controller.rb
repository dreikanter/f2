# Rotation is the remedy for a leaked posting URL (spec 006 §2): one click
# replaces the token in place and the old URL stops resolving immediately.
class Feeds::WebhookTokensController < ApplicationController
  def update
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :update?

    endpoint = feed.webhook_endpoint or raise ActiveRecord::RecordNotFound
    endpoint.rotate!

    redirect_to feed_path(feed), success: "Here's your new posting link. The old one no longer works."
  end
end
