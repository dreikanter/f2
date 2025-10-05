class GroupPurgeJob < ApplicationJob
  queue_as :default

  def perform(access_token_id, target_group)
    access_token = AccessToken.find_by(id: access_token_id)
    return unless access_token

    client = FreefeedClient.new(host: access_token.host, token: access_token.token_value)

    # Find all posts for the specified group with non-blank freefeed_post_id
    posts = Post.joins(:feed)
                .where(feeds: { access_token_id: access_token_id, target_group: target_group })
                .where.not(freefeed_post_id: [nil, ""])

    posts.find_each do |post|
      begin
        client.delete_post(post.freefeed_post_id)
        post.update!(freefeed_post_id: nil)
      rescue FreefeedClient::Error => e
        Rails.logger.error("Failed to withdraw post #{post.id} from FreeFeed: #{e.message}")
        # Continue with next post even if one fails
      end
    end
  end
end
