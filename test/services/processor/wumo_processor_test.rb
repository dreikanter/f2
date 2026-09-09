require "test_helper"

class Processor::WumoProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "wumo", url: "https://wumo.com/wumo?view=rss")
  end

  def entries(xml = file_fixture("feeds/wumo/feed.xml").read)
    Processor::WumoProcessor.new(feed, xml).process.entries
  end

  test "#process should recover dates and preserve identities from feeder's fixture" do
    result = entries

    assert_equal [Time.utc(2023, 7, 28), Time.utc(2023, 7, 27)], result.map(&:published_at)
    assert_equal %w[http://wumo.com/wumo/2023/07/28 http://wumo.com/wumo/2023/07/27], result.map(&:uid)
  end

  test "#process should recover the dates of every current Wumo entry" do
    result = entries(file_fixture("feeds/wumo/current.xml").read)

    assert_equal (2..8).to_a.reverse.map { |day| Time.utc(2026, 9, day) }, result.map(&:published_at)
  end

  test "#process should preserve an explicit RSS publication date" do
    xml = file_fixture("feeds/wumo/feed.xml").read.sub("<item>", "<item><pubDate>Fri, 28 Jul 2023 14:30:00 GMT</pubDate>")

    assert_equal Time.utc(2023, 7, 28, 14, 30), entries(xml).first.published_at
  end

  test "#process should leave invalid dates unknown without interrupting the batch" do
    xml = file_fixture("feeds/wumo/feed.xml").read.gsub("2023/07/28", "2023/02/30")
    result = entries(xml)

    assert_nil result.first.published_at
    assert_equal Time.utc(2023, 7, 27), result.second.published_at
  end

  test "#execute should apply the import threshold to Wumo permalink dates" do
    feed.update!(import_after: Time.utc(2026, 9, 7))
    stub_request(:get, feed.url).to_return(body: file_fixture("feeds/wumo/current.xml").read)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["http://wumo.com/wumo/2026/09/08"], feed.posts.pluck(:uid)
    assert_equal [Time.utc(2026, 9, 8)], feed.feed_entries.pluck(:published_at)
  end
end
