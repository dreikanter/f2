require "test_helper"
require "view_component/test_case"

class FeedsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call renders feed name as title for a regular feed" do
    feed = create(:feed, :disabled, user: user, name: "My Feed")
    result = render_inline(FeedsListComponent.new(feeds: [feed]))

    assert_match "My Feed", result.text
  end

  test "#call renders draft feed with source_input as title when name is blank" do
    feed = create(
      :feed,
      :draft,
      user: user,
      name: "",
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/draft-feed.xml" }
    )

    result = render_inline(FeedsListComponent.new(feeds: [feed]))

    assert_match "https://example.com/draft-feed.xml", result.text
  end

  test "#call renders 'Untitled draft' when both name and source_input are blank" do
    feed = build(
      :feed,
      :draft,
      user: user,
      name: "",
      feed_profile_key: "rss",
      params: {}
    )
    feed.save(validate: false)

    result = render_inline(FeedsListComponent.new(feeds: [feed]))

    assert_match "Untitled draft", result.text
  end

  test "#call renders draft badge for draft feeds" do
    feed = create(:feed, :draft, user: user, name: "Draft Feed")
    result = render_inline(FeedsListComponent.new(feeds: [feed]))

    badge = result.css(%([data-key="feed.#{feed.id}.draft_badge"])).first
    assert_not_nil badge, "Expected to find a draft badge for draft feed"
    assert_equal "Draft", badge.text.strip
  end

  test "#call does not render draft badge for non-draft feeds" do
    feed = create(:feed, :disabled, user: user, name: "Inactive Feed")
    result = render_inline(FeedsListComponent.new(feeds: [feed]))

    assert_empty result.css(%([data-key="feed.#{feed.id}.draft_badge"]))
  end
end
