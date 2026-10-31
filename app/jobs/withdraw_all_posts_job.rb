class WithdrawAllPostsJob < ApplicationJob
  include SetsFeedErrorContext

  queue_as :default

  def perform(feed_id, user_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    set_feed_error_context(feed)

    user = User.find_by(id: user_id)
    return unless user

    access_token = feed.access_token
    return unless access_token&.active?

    WithdrawAllPosts.new(feed, user: user).call
  end
end
