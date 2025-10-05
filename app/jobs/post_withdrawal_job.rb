class PostWithdrawalJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = Post.find(post_id)
    access_token = post.feed.access_token
    client = FreefeedClient.new(host: access_token.host, token: access_token.token_value)

    client.delete_post(post.freefeed_post_id)
  rescue FreefeedClient::Error => e
    Rails.logger.error("Failed to withdraw post #{post_id} from FreeFeed: #{e.message}")
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("Post #{post_id} not found")
  end
end
