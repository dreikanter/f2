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

  test "#call should render Continue setup and Discard affordances for draft rows" do
    feed = create(:feed, :draft, user: user, name: "Draft Feed")

    with_request_url("/feeds") do
      result = render_inline(FeedsListComponent.new(feeds: [feed]))

      continue_link = result.css(%([data-key="feed.#{feed.id}.continue_setup"])).first
      assert_not_nil continue_link, "Expected Continue setup link"
      assert_equal "Continue setup", continue_link.text.strip
      assert_equal Rails.application.routes.url_helpers.edit_feed_path(feed), continue_link["href"]

      discard_button = result.css(%([data-key="feed.#{feed.id}.discard"])).first
      assert_not_nil discard_button, "Expected Discard button"
      assert_equal "Discard", discard_button.text.strip

      discard_form = discard_button.ancestors("form").first
      assert_not_nil discard_form, "Expected Discard button to be inside a form"
      assert_equal Rails.application.routes.url_helpers.feed_path(feed), discard_form["action"]
      assert_equal "Discard this draft? No data will be lost since it hasn't been activated.",
                   discard_form["data-turbo-confirm"]
      assert_equal "post", discard_form["method"]
      assert_equal "delete", discard_form.css("input[name='_method']").first&.[]("value")
    end
  end

  test "#call should not render those affordances for non-draft rows" do
    feed = create(:feed, :disabled, user: user, name: "Inactive Feed")

    with_request_url("/feeds") do
      result = render_inline(FeedsListComponent.new(feeds: [feed]))

      assert_empty result.css(%([data-key="feed.#{feed.id}.continue_setup"]))
      assert_empty result.css(%([data-key="feed.#{feed.id}.discard"]))
    end
  end
end
