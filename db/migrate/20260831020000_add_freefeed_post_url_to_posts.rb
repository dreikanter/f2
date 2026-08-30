# Persists the full published post URL instead of deriving it from the feed's
# access token host at read time, so it stays intact after the token is
# deleted. Existing published posts are backfilled while their token is
# still around.
class AddFreefeedPostUrlToPosts < ActiveRecord::Migration[8.2]
  def up
    add_column :posts, :freefeed_post_url, :string

    execute <<~SQL
      UPDATE posts
      SET freefeed_post_url = access_tokens.host || '/' || feeds.target_group || '/' || posts.freefeed_post_id
      FROM feeds
      INNER JOIN access_tokens ON access_tokens.id = feeds.access_token_id
      WHERE feeds.id = posts.feed_id
        AND posts.freefeed_post_id IS NOT NULL
        AND feeds.target_group IS NOT NULL
    SQL
  end

  def down
    remove_column :posts, :freefeed_post_url
  end
end
