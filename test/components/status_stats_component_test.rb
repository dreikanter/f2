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

    assert_includes result.css(".ff-list-group__title").map(&:text), "Total feeds"
    assert_includes result.css(".ff-list-group__trailing-text").map(&:text), "3"
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

      titles = result.css(".ff-list-group__title").map(&:text)
      values = result.css(".ff-list-group__trailing-text").map(&:text)

      assert_includes titles, "Total imported posts"
      assert_includes values, "5"
      assert_includes titles, "Total published posts"
      assert_includes values, "4"
      recent_index = titles.index("Most recent post publication")
      assert recent_index, "Expected Most recent post publication title"
      assert_includes values[recent_index], "ago"
      average_index = titles.index("Average posts per day (last week)")
      assert average_index
      assert_equal "1.5", values[average_index]
    end
  end
end
