require "test_helper"

class FeedRefreshWorkflowTwitterTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "twitter", url: "testuser")
  end

  test "#execute should leave posts retryable when a permalink is unavailable" do
    html = file_fixture("feeds/twitter/timeline.html").read
    missing_link_html = html.sub('"permalink": "https://twitter.com/testuser/status/1002",', "")
    stub_request(:get, "https://syndication.twitter.com/srv/timeline-profile/screen-name/testuser")
      .to_return(body: missing_link_html, status: 200)

    assert_raises(Processor::TwitterProcessor::InvalidPermalink) do
      FeedRefreshWorkflow.new(feed).execute
    end

    assert_empty feed.feed_entries
    assert_empty FeedEntryUid.where(feed: feed)
    assert_empty feed.posts
    event = feed.events.find_by!(type: "feed_refresh")
    assert_equal "failed", event.metadata["status"]
    assert_equal "process_feed_contents", event.metadata.dig("error", "stage")

    stub_request(:get, "https://syndication.twitter.com/srv/timeline-profile/screen-name/testuser")
      .to_return(body: html, status: 200)
    FeedRefreshWorkflow.new(feed).execute

    assert_equal %w[1001 1002 1003], feed.feed_entries.order(:uid).pluck(:uid)
    assert_equal %w[1001 1002 1003], FeedEntryUid.where(feed: feed).order(:uid).pluck(:uid)
    assert_equal %w[1001 1002 1003], feed.posts.where(status: :enqueued).order(:uid).pluck(:uid)
  end

  test "#execute should enqueue posts with whitespace around their permalinks" do
    html = file_fixture("feeds/twitter/timeline.html").read
      .sub("https://x.com/testuser/status/1001", ' https://x.com/testuser/status/1001\n')
    stub_request(:get, "https://syndication.twitter.com/srv/timeline-profile/screen-name/testuser")
      .to_return(body: html, status: 200)

    FeedRefreshWorkflow.new(feed).execute

    post = feed.posts.find_by!(uid: "1001")
    assert_equal "enqueued", post.status
    assert_equal "https://x.com/testuser/status/1001", post.source_url
    assert_equal "https://x.com/testuser/status/1001", feed.feed_entries.find_by!(uid: "1001").raw_data["url"]
  end
end
