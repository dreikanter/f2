require "test_helper"
require "view_component/test_case"

class GlobalStatsComponentTest < ViewComponent::TestCase
  test "#render should include all metrics" do
    result = render_inline(GlobalStatsComponent.new)

    %w[
      total_users
      total_feeds
      total_imported_posts
      total_published_posts
      posts_last_week
      most_recent_repost
    ].each do |key|
      assert_not_nil result.css(%([data-key="stats.#{key}"])).first, "expected stats.#{key} to be rendered"
    end
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(GlobalStatsComponent.new)

    mobile_layout = result.css(".md\\:hidden").first
    assert_not_nil mobile_layout
    assert_includes result.css(".md\\:hidden [data-key=\"stats.total_users.label\"]").first.text, "Total users"
    assert_includes result.css(".md\\:hidden [data-key=\"stats.total_feeds.label\"]").first.text, "Total feeds"
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(GlobalStatsComponent.new)

    desktop_layout = result.css(".hidden.md\\:flex").first
    assert_not_nil desktop_layout
    assert_equal "Users", result.css(".hidden.md\\:flex [data-key=\"stats.total_users.label\"]").first.text
    assert_equal "Feeds", result.css(".hidden.md\\:flex [data-key=\"stats.total_feeds.label\"]").first.text
    assert_equal "Imported", result.css(".hidden.md\\:flex [data-key=\"stats.total_imported_posts.label\"]").first.text
  end

  test "#render should aggregate counts across all users" do
    first_feed = create(:feed, user: create(:user))
    second_feed = create(:feed, user: create(:user))
    create(:post, :published, feed: first_feed)
    create(:post, feed: second_feed)

    result = render_inline(GlobalStatsComponent.new)

    assert_equal User.count.to_s, result.css(".hidden.md\\:flex [data-key=\"stats.total_users.value\"]").first.text
    assert_equal Feed.count.to_s, result.css(".hidden.md\\:flex [data-key=\"stats.total_feeds.value\"]").first.text
    assert_equal "2", result.css(".hidden.md\\:flex [data-key=\"stats.total_imported_posts.value\"]").first.text
    assert_equal "1", result.css(".hidden.md\\:flex [data-key=\"stats.total_published_posts.value\"]").first.text
  end

  test "#render should display fallback value when no published posts" do
    result = render_inline(GlobalStatsComponent.new)

    recent_value = result.css('[data-key="stats.most_recent_repost.value"]').first.text
    assert_equal "—", recent_value
  end
end
