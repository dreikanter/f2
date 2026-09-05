require "test_helper"
require_relative "../../db/migrate/20260905190000_add_feed_to_feed_previews"

class FeedPreviewFeedMigrationTest < ActiveSupport::TestCase
  test "#change should roll back and reapply while preserving existing previews" do
    preview = create(:feed_preview, :completed)
    digest = preview.params_digest
    migration = AddFeedToFeedPreviews.new

    migration.migrate(:down)
    assert_not FeedPreview.connection.column_exists?(:feed_previews, :feed_id)
    migration.migrate(:up)
    FeedPreview.reset_column_information

    assert preview.reload.ready?
    assert_nil preview.feed_id
    assert_equal digest, preview.params_digest
    assert FeedPreview.connection.foreign_key_exists?(:feed_previews, :feeds)
  ensure
    FeedPreview.reset_column_information
  end
end
