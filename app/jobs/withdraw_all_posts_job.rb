class WithdrawAllPostsJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    WithdrawAllPosts.new(feed).call
  end
end
