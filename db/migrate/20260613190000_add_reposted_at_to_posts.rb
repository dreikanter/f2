class AddRepostedAtToPosts < ActiveRecord::Migration[8.2]
  def up
    add_column :posts, :reposted_at, :datetime
    add_index :posts, [:feed_id, :reposted_at]

    # Backfill the repost moment for already-published posts. updated_at is the
    # best available proxy: until now it was what Post#reposted_at returned.
    execute(<<~SQL.squish)
      UPDATE posts
      SET reposted_at = updated_at
      WHERE status = #{Post.statuses.fetch(:published)}
        AND reposted_at IS NULL
    SQL
  end

  def down
    remove_index :posts, [:feed_id, :reposted_at]
    remove_column :posts, :reposted_at
  end
end
