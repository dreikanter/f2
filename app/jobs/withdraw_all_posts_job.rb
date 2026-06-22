class WithdrawAllPostsJob < ApplicationJob
  queue_as :default

  def perform(feed_id, user_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    user = User.find_by(id: user_id)
    return unless user

    access_token = feed.access_token
    return unless access_token&.active?

    WithdrawAllPosts.new(feed, user: user).call
  end
end
