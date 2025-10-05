class GroupPurgeJob < ApplicationJob
  queue_as :default

  def perform(access_token_id, target_group)
    access_token = AccessToken.find(access_token_id)
    client = FreefeedClient.new(host: access_token.host, token: access_token.token_value)

    # Find all published posts for the specified group
    posts = Post.joins(:feed)
                .where(feeds: { access_token_id: access_token_id, target_group: target_group })
                .where(status: :published)
                .where.not(freefeed_post_id: nil)

    posts.find_each do |post|
      begin
        client.delete_post(post.freefeed_post_id)
        post.update!(status: :deleted)
      rescue FreefeedClient::Error => e
        Rails.logger.error("Failed to delete post #{post.id}: #{e.message}")
        # Continue with next post even if one fails
      end
    end
  end
end
