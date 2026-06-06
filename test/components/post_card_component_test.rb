require "test_helper"
require "view_component/test_case"

class PostCardComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, target_group: "xkcd")
  end

  def post
    @post ||= create(:post, :published, feed: feed, content: "Flag Design", source_url: "https://xkcd.com/3250/")
  end

  test "#render should use dom_id as element id for turbo targeting" do
    result = render_inline PostCardComponent.new(post: post)

    assert_not_empty result.css("##{ActionView::RecordIdentifier.dom_id(post)}")
  end

  test "#render should link title to post detail page" do
    result = render_inline PostCardComponent.new(post: post)

    link = result.at_css("a[href*='/posts/']")
    assert_not_nil link
    assert_includes link.text, "Flag Design"
  end

  test "#render should show @group label with display name title when show_feed is true" do
    result = render_inline PostCardComponent.new(post: post, show_feed: true)

    group_link = result.at_css("a[href*='/feeds/']")
    assert_not_nil group_link
    assert_equal "@xkcd", group_link.text.strip
    assert_equal feed.display_name, group_link["title"]
  end

  test "#render should hide group label when show_feed is false" do
    result = render_inline PostCardComponent.new(post: post, show_feed: false)

    assert_nil result.at_css("a[href*='/feeds/']")
  end

  test "#render should show attachment count icon when attachments present" do
    post_with_attachments = create(:post, :with_attachments, feed: feed)
    result = render_inline PostCardComponent.new(post: post_with_attachments)

    assert_not_empty result.css("span.flex.items-center.gap-1")
  end

  test "#render should show Withdrawn badge for withdrawn posts" do
    withdrawn_post = create(:post, feed: feed, status: :withdrawn)
    result = render_inline PostCardComponent.new(post: withdrawn_post)

    assert_includes result.text, "Withdrawn"
  end

  test "#render should show footer when post has a source url" do
    result = render_inline PostCardComponent.new(post: post)

    assert_not_empty result.css(".border-t.border-slate-200")
  end

  test "#render should link origin time to the source publication" do
    published_post = create(:post, :published, feed: feed, source_url: "https://xkcd.com/3250/",
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: published_post)

    origin_link = result.at_css("a[href='https://xkcd.com/3250/']")
    assert_not_nil origin_link
    assert_includes origin_link.text.gsub(/\s+/, " "), "Source (11h)"
  end

  test "#render should link repost time to the freefeed post" do
    published_post = create(:post, :published, feed: feed,
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: published_post)

    repost_link = result.at_css("a[href='#{published_post.freefeed_url}']")
    assert_not_nil repost_link
    assert_includes repost_link.text.gsub(/\s+/, " "), "Repost (10h)"
  end

  test "#render should not show a repost time for unpublished posts" do
    draft_post = create(:post, feed: feed, status: :draft, published_at: 11.hours.ago)
    result = render_inline PostCardComponent.new(post: draft_post)

    text = result.text.gsub(/\s+/, " ")
    assert_includes text, "Source (11h)"
    assert_not_includes text, "Repost"
  end
end
