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

  test "#render should show attachment count for reposted posts with attachments" do
    post_with_attachments = create(:post, :published, :with_attachments, feed: feed)
    result = render_inline PostCardComponent.new(post: post_with_attachments)

    assert_equal "2 attachments", result.at_css('[data-key="post.attachments"]').text.strip
  end

  test "#render should show comment count for reposted posts with comments" do
    post_with_comments = create(:post, :published, :with_comments, feed: feed)
    result = render_inline PostCardComponent.new(post: post_with_comments)

    assert_equal "1 comment", result.at_css('[data-key="post.comments"]').text.strip
  end

  test "#render should separate footer items with middots" do
    post_with_attachments = create(:post, :published, :with_attachments, feed: feed,
      source_url: "https://xkcd.com/3250/")
    result = render_inline PostCardComponent.new(post: post_with_attachments)

    # status · Source · attachments => two separators, hidden from assistive tech.
    middots = result.css("span").select { |span| span.text.strip == "·" }
    assert_equal 2, middots.size
    assert(middots.all? { |middot| middot["aria-hidden"] == "true" })
  end

  test "#render should not show attachment or comment counts when none" do
    result = render_inline PostCardComponent.new(post: post)

    assert_nil result.at_css('[data-key="post.attachments"]')
    assert_nil result.at_css('[data-key="post.comments"]')
  end

  test "#render should not show counts for failed posts even with attachments" do
    failed_post = create(:post, :failed, :with_attachments, feed: feed)
    result = render_inline PostCardComponent.new(post: failed_post)

    assert_nil result.at_css('[data-key="post.attachments"]')
  end

  test "#render should show Withdrawn badge for withdrawn posts" do
    withdrawn_post = create(:post, feed: feed, status: :withdrawn)
    result = render_inline PostCardComponent.new(post: withdrawn_post)

    assert_includes result.text, "Withdrawn"
  end

  test "#render should use a gray background for withdrawn posts" do
    withdrawn_post = create(:post, feed: feed, status: :withdrawn)
    result = render_inline PostCardComponent.new(post: withdrawn_post)

    assert_not_empty result.css("##{ActionView::RecordIdentifier.dom_id(withdrawn_post)}.bg-slate-50")
  end

  test "#render should offer Details and Delete actions for a published post" do
    Current.session = build(:session, user: user)
    result = render_inline PostCardComponent.new(post: post)

    menu_items = result.css('[role="menuitem"]').map { |item| item.text.strip }
    assert_includes menu_items, "Details"
    assert_includes menu_items, "Delete…"
  end

  test "#render should render the delete modal for a published post" do
    Current.session = build(:session, user: user)
    result = render_inline PostCardComponent.new(post: post)

    assert_not_empty result.css("##{PostDeleteModalComponent.modal_id(post)}")
  end

  test "#render should offer Delete for a failed post" do
    Current.session = build(:session, user: user)
    failed_post = create(:post, :failed, feed: feed)
    result = render_inline PostCardComponent.new(post: failed_post)

    menu_items = result.css('[role="menuitem"]').map { |item| item.text.strip }
    assert_includes menu_items, "Delete…"
  end

  test "#render should not offer Delete for an unpublished post" do
    Current.session = build(:session, user: user)
    draft_post = create(:post, feed: feed, status: :draft)
    result = render_inline PostCardComponent.new(post: draft_post)

    menu_items = result.css('[role="menuitem"]').map { |item| item.text.strip }
    assert_includes menu_items, "Details"
    assert_not_includes menu_items, "Delete…"
  end

  test "#render should show footer when post has a source url" do
    result = render_inline PostCardComponent.new(post: post)

    assert_not_empty result.css(".border-t.border-slate-200")
  end

  test "#render should link the source without a timestamp" do
    published_post = create(:post, :published, feed: feed, source_url: "https://xkcd.com/3250/",
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: published_post)

    source_link = result.at_css("a[href='https://xkcd.com/3250/']")
    assert_not_nil source_link
    assert_equal "Source", source_link.text.strip
  end

  test "#render should label published posts as reposted and link to the freefeed post" do
    published_post = create(:post, :published, feed: feed,
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: published_post)

    status_link = result.at_css("a[href='#{published_post.freefeed_url}']")
    assert_not_nil status_link
    assert_includes status_link.text.gsub(/\s+/, " "), "Reposted (10h)"
    assert_not_empty status_link.css("svg.text-green-600")
  end

  test "#render should keep the duration tight against its parentheses" do
    published_post = create(:post, :published, feed: feed,
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: published_post)

    # The label, parens and time tag share one inline wrapper that carries no
    # flex gap, so the duration cannot drift away from its parentheses.
    wrapper = result.at_css('[data-key="post.status"] time').parent
    assert_equal "Reposted (10h)", wrapper.text.strip
    assert_not_includes wrapper["class"].to_s, "gap"
  end

  test "#render should show the reposted status as plain text when freefeed url is missing" do
    # A purged post stays published but loses its freefeed_post_id (see GroupPurgeJob)
    purged_post = create(:post, :published, feed: feed, freefeed_post_id: nil,
      published_at: 11.hours.ago, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: purged_post)

    assert_nil purged_post.freefeed_url
    status = result.at_css('[data-key="post.status"]')
    assert_includes status.text.gsub(/\s+/, " "), "Reposted (10h)"
    assert_equal "span", status.name
  end

  test "#render should label failed posts as failed with a red icon" do
    failed_post = create(:post, :failed, feed: feed, updated_at: 10.hours.ago)
    result = render_inline PostCardComponent.new(post: failed_post)

    status = result.at_css('[data-key="post.status"]')
    assert_includes status.text.gsub(/\s+/, " "), "Failed (10h)"
    assert_not_empty status.css("svg.text-red-600")
  end
end
