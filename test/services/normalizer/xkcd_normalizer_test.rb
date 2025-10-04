require "test_helper"

# TBD: Use snapshot testing
class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_file_name
    "sample_xkcd.xml"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "sholuld match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "Ping", post.content
    assert_equal ["https://imgs.xkcd.com/comics/ping.png"], post.attachment_urls
    assert_equal ["Progress on getting shipwrecked sailors to adopt ICMPv6 has been slow."], post.comments
    assert_equal "https://xkcd.com/3150/", post.source_url
    assert post.enqueued?
    assert_equal [], post.validation_errors
  end
end
