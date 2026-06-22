class AddPostCounterCachesToFeeds < ActiveRecord::Migration[8.2]
  def up
    add_column :feeds, :imported_posts_count, :integer, null: false, default: 0
    add_column :feeds, :published_posts_count, :integer, null: false, default: 0

    execute(<<~SQL.squish)
      UPDATE feeds
      SET
        imported_posts_count = (SELECT COUNT(*) FROM posts WHERE posts.feed_id = feeds.id),
        published_posts_count = (SELECT COUNT(*) FROM posts WHERE posts.feed_id = feeds.id AND posts.status = #{Post.statuses.fetch(:published)})
    SQL
  end

  def down
    remove_column :feeds, :imported_posts_count
    remove_column :feeds, :published_posts_count
  end
end
