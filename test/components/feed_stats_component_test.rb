require "test_helper"
require "view_component/test_case"
class FeedStatsComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def feed
    @feed ||= create(:feed).tap do |f|
      create(:feed_entry, feed: f, created_at: 1.hour.ago)
    end
  end

  def feed_with_posts
    @feed_with_posts ||= create(:feed).tap do |f|
      create(:feed_entry, feed: f, created_at: 1.hour.ago)
      create(:post, :published, feed: f, published_at: 2.hours.ago)
      create(:post, feed: f, published_at: 3.hours.ago)
    end
  end

  test "#render should include all metrics" do
    travel_to Time.current do
      result = render_inline(FeedStatsComponent.new(feed: feed_with_posts))

      last_refresh = result.css('[data-key="stats.last_refresh"]').first
      assert_not_nil last_refresh

      most_recent = result.css('[data-key="stats.most_recent_post"]').first
      assert_not_nil most_recent

      imported = result.css('[data-key="stats.imported_posts"]').first
      assert_not_nil imported
      assert_equal "2", result.css('[data-key="stats.imported_posts.value"]').first.text.strip

      published = result.css('[data-key="stats.published_posts"]').first
      assert_not_nil published
      assert_equal "1", result.css('[data-key="stats.published_posts.value"]').first.text.strip
    end
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(FeedStatsComponent.new(feed: feed))

    mobile_layout = result.css(".md\\:hidden").first
    assert_not_nil mobile_layout
    assert_equal "Last refresh", result.css(".md\\:hidden [data-key=\"stats.last_refresh.label\"]").first.text
    assert_equal "Latest imported post", result.css(".md\\:hidden [data-key=\"stats.most_recent_post.label\"]").first.text
    assert_equal "Imported posts", result.css(".md\\:hidden [data-key=\"stats.imported_posts.label\"]").first.text
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(FeedStatsComponent.new(feed: feed))

    desktop_layout = result.css(".hidden.md\\:flex").first
    assert_not_nil desktop_layout
    assert_equal "Refreshed", result.css(".hidden.md\\:flex [data-key=\"stats.last_refresh.label\"]").first.text
    assert_equal "Latest", result.css(".hidden.md\\:flex [data-key=\"stats.most_recent_post.label\"]").first.text
    assert_equal "Imported", result.css(".hidden.md\\:flex [data-key=\"stats.imported_posts.label\"]").first.text
    assert_equal "Published", result.css(".hidden.md\\:flex [data-key=\"stats.published_posts.label\"]").first.text
  end

  test "#render should display fallback values for missing data" do
    feed_without_data = create(:feed)

    result = render_inline(FeedStatsComponent.new(feed: feed_without_data))

    last_refresh_value = result.css('[data-key="stats.last_refresh.value"]').first.text
    assert_equal "Never", last_refresh_value

    most_recent_value = result.css('[data-key="stats.most_recent_post.value"]').first.text
    assert_equal "None", most_recent_value
  end
end
