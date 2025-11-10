require "test_helper"
require "view_component/test_case"
class UserStatsComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def user
    @user ||= create(:user)
  end

  test "#render should include all metrics" do
    result = render_inline(UserStatsComponent.new(user: user))

    feeds = result.css('[data-key="stats.total_feeds"]').first
    assert_not_nil feeds

    imported = result.css('[data-key="stats.total_imported_posts"]').first
    assert_not_nil imported

    published = result.css('[data-key="stats.total_published_posts"]').first
    assert_not_nil published

    recent = result.css('[data-key="stats.most_recent_post_publication"]').first
    assert_not_nil recent

    average = result.css('[data-key="stats.average_posts_per_day"]').first
    assert_not_nil average
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(UserStatsComponent.new(user: user))

    mobile_layout = result.css(".md\\:hidden").first
    assert_not_nil mobile_layout
    assert_includes result.css(".md\\:hidden [data-key=\"stats.total_feeds.label\"]").first.text, "Total feeds"
    assert_includes result.css(".md\\:hidden [data-key=\"stats.total_imported_posts.label\"]").first.text, "Total imported posts"
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(UserStatsComponent.new(user: user))

    desktop_layout = result.css(".hidden.md\\:flex").first
    assert_not_nil desktop_layout
    assert_equal "Feeds", result.css(".hidden.md\\:flex [data-key=\"stats.total_feeds.label\"]").first.text
    assert_equal "Imported", result.css(".hidden.md\\:flex [data-key=\"stats.total_imported_posts.label\"]").first.text
    assert_equal "Published", result.css(".hidden.md\\:flex [data-key=\"stats.total_published_posts.label\"]").first.text
  end

  test "#render should display fallback value when no published posts" do
    user_without_posts = create(:user)

    result = render_inline(UserStatsComponent.new(user: user_without_posts))

    recent_value = result.css('[data-key="stats.most_recent_post_publication.value"]').first.text
    assert_equal "—", recent_value
  end
end
