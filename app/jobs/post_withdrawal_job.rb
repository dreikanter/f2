class PostWithdrawalJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post

    client = post.feed.access_token.build_client
    client.delete_post(post.freefeed_post_id)
  rescue FreefeedClient::Error => e
    Rails.logger.error("Failed to withdraw post #{post_id} from FreeFeed: #{e.message}")
  end
end
