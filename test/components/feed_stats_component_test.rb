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
    @feed_with_posts ||= begin
      f = create(:feed).tap do |feed|
        create(:feed_entry, feed: feed, created_at: 1.hour.ago)
        create(:post, :published, feed: feed, published_at: 2.hours.ago, reposted_at: 1.hour.ago)
        create(:post, feed: feed, published_at: 3.hours.ago)
      end
      f.reload
    end
  end

  test "#render should include all metrics" do
    travel_to Time.current do
      result = render_inline(FeedStatsComponent.new(feed: feed_with_posts))

      last_refresh = result.css('[data-key="stats.last_refresh"]').first
      assert_not_nil last_refresh

      most_recent = result.css('[data-key="stats.most_recent_repost"]').first
      assert_not_nil most_recent
      assert_equal "1h", result.css('[data-key="stats.most_recent_repost.value"]').first.text.strip

      imported = result.css('[data-key="stats.imported_posts"]').first
      assert_not_nil imported
      assert_equal "2", result.css('[data-key="stats.imported_posts.value"]').first.text.strip

      published = result.css('[data-key="stats.published_posts"]').first
      assert_not_nil published
      assert_equal "1", result.css('[data-key="stats.published_posts.value"]').first.text.strip

      last_week = result.css('[data-key="stats.posts_last_week"]').first
      assert_not_nil last_week
      assert_equal "2", result.css('[data-key="stats.posts_last_week.value"]').first.text.strip
    end
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(FeedStatsComponent.new(feed: feed))

    mobile_layout = result.css(".md\\:hidden").first
    assert_not_nil mobile_layout
    assert_equal "Last refresh", result.css(".md\\:hidden [data-key=\"stats.last_refresh.label\"]").first.text
    assert_equal "Most recent repost", result.css(".md\\:hidden [data-key=\"stats.most_recent_repost.label\"]").first.text
    assert_equal "Imported posts", result.css(".md\\:hidden [data-key=\"stats.imported_posts.label\"]").first.text
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(FeedStatsComponent.new(feed: feed))

    desktop_layout = result.css(".hidden.md\\:flex").first
    assert_not_nil desktop_layout
    assert_equal "Refreshed", result.css(".hidden.md\\:flex [data-key=\"stats.last_refresh.label\"]").first.text
    assert_equal "Recent", result.css(".hidden.md\\:flex [data-key=\"stats.most_recent_repost.label\"]").first.text
    assert_equal "Imported", result.css(".hidden.md\\:flex [data-key=\"stats.imported_posts.label\"]").first.text
    assert_equal "Published", result.css(".hidden.md\\:flex [data-key=\"stats.published_posts.label\"]").first.text
    assert_equal "Last week", result.css(".hidden.md\\:flex [data-key=\"stats.posts_last_week.label\"]").first.text
  end

  test "#render should display fallback values for missing data" do
    feed_without_data = create(:feed)

    result = render_inline(FeedStatsComponent.new(feed: feed_without_data))

    last_refresh_value = result.css('[data-key="stats.last_refresh.value"]').first.text
    assert_equal "–", last_refresh_value

    most_recent_value = result.css('[data-key="stats.most_recent_repost.value"]').first.text
    assert_equal "–", most_recent_value
  end

  test "#render should mute zero counts and fallback values" do
    feed_without_data = create(:feed)

    result = render_inline(FeedStatsComponent.new(feed: feed_without_data))

    %w[imported_posts published_posts posts_last_week last_refresh most_recent_repost].each do |key|
      result.css(%([data-key="stats.#{key}.value"])).each do |value|
        assert_includes value["class"], "text-muted", "expected #{key} value to be muted"
      end
    end
  end

  test "#render should not mute non-zero values" do
    result = render_inline(FeedStatsComponent.new(feed: feed_with_posts))

    %w[imported_posts published_posts posts_last_week most_recent_repost].each do |key|
      result.css(%([data-key="stats.#{key}.value"])).each do |value|
        assert_not_includes value["class"], "text-muted", "expected #{key} value not to be muted"
      end
    end
  end
end
