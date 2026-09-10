require "test_helper"

class HackernewsFeedTest < ActiveSupport::TestCase
  URL = "https://news.ycombinator.com/best"

  test "identification should recognize the best-stories source" do
    result = FeedProfileDetector.call(input: URL)

    assert_equal ["hackernews"], result.candidates.map(&:profile_key)
    assert_not ProfileMatcher::HackernewsProfileMatcher.new("https://news.ycombinator.com/newest").match?
  end

  test "processing should require more than 300 points and omit removed items" do
    feed = build(:feed, feed_profile_key: "hackernews", url: URL)
    entries = feed.processor_instance(items).process.entries

    assert_equal %w[100003 100001], entries.map(&:uid)
    assert_equal Time.at(1788948002).utc, entries.first.published_at
  end

  test "preview should retain article destinations and text-only discussion links" do
    preview = create(:feed_preview, feed_profile_key: "hackernews", params: { "url" => URL })
    stub_api

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    posts = preview.posts_data
    assert_equal "Sample discussion - https://news.ycombinator.com/item?id=100003", posts.first.fetch("content")
    assert_equal "Sample article - https://example.org/article", posts.second.fetch("content")
    assert_equal ["301 points / https://news.ycombinator.com/item?id=100001"], posts.second.fetch("comments")
  end

  test "import should apply the cutoff to the original story time" do
    feed = create(:feed, feed_profile_key: "hackernews", url: URL, import_after: Time.at(1788948001).utc)
    stub_api

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["100003"], feed.feed_entries.pluck(:uid)
    assert_equal [Time.at(1788948002).utc], feed.posts.pluck(:published_at)
  end

  private

  def items
    JSON.parse(file_fixture("feeds/hackernews/items.json").read)
  end

  def stub_api
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/beststories.json").to_return(body: "[100001,100002,100003,100004,100005]")
    stub_request(:get, %r{https://hacker-news\.firebaseio\.com/v0/item/10000[1-5]\.json}).to_return do |request|
      index = File.basename(request.uri.path).to_i - 100001
      { body: items[index].to_json }
    end
  end
end
