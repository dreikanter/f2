# Replaces a webhook credential after suspected disclosure or routine rotation.
# The old token stops authenticating immediately.
class Feeds::WebhookTokensController < ApplicationController
  def update
    feed = Current.user.feeds.find(params[:feed_id])
    authorize feed, :update?

    endpoint = feed.webhook_endpoint or raise ActiveRecord::RecordNotFound
    endpoint.rotate!

    redirect_to feed_path(feed), success: "Here's your new webhook token. The old token no longer works."
  end
end
