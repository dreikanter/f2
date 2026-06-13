class AddPublishedPostsCountToFeedMetrics < ActiveRecord::Migration[8.2]
  def up
    add_column :feed_metrics, :published_posts_count, :integer, default: 0, null: false

    # Backfill from the posts that have actually been reposted to FreeFeed,
    # bucketed by the day they were published there.
    execute(<<~SQL.squish)
      INSERT INTO feed_metrics (feed_id, date, published_posts_count, created_at, updated_at)
      SELECT feed_id, reposted_at::date, COUNT(*), NOW(), NOW()
      FROM posts
      WHERE status = #{Post.statuses.fetch(:published)}
        AND reposted_at IS NOT NULL
      GROUP BY feed_id, reposted_at::date
      ON CONFLICT (feed_id, date)
      DO UPDATE SET published_posts_count = EXCLUDED.published_posts_count, updated_at = NOW()
    SQL
  end

  def down
    remove_column :feed_metrics, :published_posts_count
  end
end
