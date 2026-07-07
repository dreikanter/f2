class AllowNullPostsSourceUrl < ActiveRecord::Migration[8.2]
  # Digest/standing-query posts carry source_url = null end-to-end (spec 005 §3).
  # The down side backfills any existing NULLs to "" before restoring NOT NULL,
  # so a rollback after digest rows exist doesn't fail.
  def up
    change_column_null :posts, :source_url, true
  end

  def down
    change_column_null :posts, :source_url, false, ""
  end
end
