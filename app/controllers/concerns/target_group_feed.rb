# The feed the target-group selector renders against. The feed form asks for
# the selector while the feed is still a draft, so an unsaved feed stands in
# when there is nothing to look up.
module TargetGroupFeed
  extend ActiveSupport::Concern

  private

  def feed
    @feed ||= current_user.feeds.find_by(id: params[:feed_id]) || current_user.feeds.build
  end
end
