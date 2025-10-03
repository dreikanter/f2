require "test_helper"

class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  def setup
    @feed = create(:feed)
    @processor = Processor::RssProcessor.new(@feed, file_fixture("sample_xkcd.xml").read)
    @feed_entries = @processor.process
  end

  def feed_entry(index)
    entry = @feed_entries[index]
    entry.save!
    entry
  end

  test "normalizes first comic from fixture (Ping)" do
    entry = feed_entry(0)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "Progress on getting shipwrecked sailors to adopt ICMPv6 has been slow.", post.content
    assert_equal ["https://imgs.xkcd.com/comics/ping.png"], post.attachment_urls
    assert_equal "https://xkcd.com/3150/", post.source_url
    assert post.enqueued?
    assert_equal [], post.validation_errors
  end

  test "normalizes second comic from fixture with HTML entities" do
    entry = feed_entry(1)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal '"Measure zero times, cut zero times." --carpenter who has achieved enlightenment and realized the wood is fine where it is', post.content
    assert_equal ["https://imgs.xkcd.com/comics/measure_twice_cut_once.png"], post.attachment_urls
    assert_equal "https://xkcd.com/3149/", post.source_url
    assert post.enqueued?
  end

  test "normalizes third comic from fixture" do
    entry = feed_entry(2)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "I'm trying to share my footage of the full run to prove it's not tool-assisted, but the uploader has problems with video lengths of more than a decade.", post.content
    assert_equal ["https://imgs.xkcd.com/comics/100_all_achievements.png"], post.attachment_urls
    assert_equal "https://xkcd.com/3148/", post.source_url
    assert post.enqueued?
  end
end
