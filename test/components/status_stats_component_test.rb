require "test_helper"
require "view_component/test_case"
class StatusStatsComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "#render should include required metrics" do
    result = render_inline(
      StatusStatsComponent.new(
        total_feeds_count: 3,
        total_imported_posts_count: 0,
        total_published_posts_count: 0,
        most_recent_post_published_at: nil,
        average_posts_per_day_last_week: nil
      )
    )

    item = result.css('[data-key="stats.total_feeds"]').first
    assert_not_nil item
    assert_equal "Total feeds", result.css('[data-key="stats.total_feeds.label"]').first.text
    assert_equal "3", result.css('[data-key="stats.total_feeds.value"]').first.text
  end

  test "#render should include optional metrics when available" do
    travel_to Time.current do
      result = render_inline(
        StatusStatsComponent.new(
          total_feeds_count: 2,
          total_imported_posts_count: 5,
          total_published_posts_count: 4,
          most_recent_post_published_at: 1.hour.ago,
          average_posts_per_day_last_week: 1.5
        )
      )

      imported = result.css('[data-key="stats.total_imported_posts"]').first
      assert_not_nil imported
      assert_equal "5", result.css('[data-key="stats.total_imported_posts.value"]').first.text

      published = result.css('[data-key="stats.total_published_posts"]').first
      assert_not_nil published
      assert_equal "4", result.css('[data-key="stats.total_published_posts.value"]').first.text

      recent = result.css('[data-key="stats.most_recent_post_publication"]').first
      assert_not_nil recent
      assert_match(/ago/, result.css('[data-key="stats.most_recent_post_publication.value"]').first.text)

      average = result.css('[data-key="stats.average_posts_per_day"]').first
      assert_not_nil average
      assert_equal "1.5", result.css('[data-key="stats.average_posts_per_day.value"]').first.text
    end
  end
end
