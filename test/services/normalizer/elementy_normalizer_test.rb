require "test_helper"

class Normalizer::ElementyNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries
  include DnsTestHelper

  def fixture_dir
    "feeds/elementy"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_return(status: 200, body: file_fixture("feeds/elementy/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::ElementyNormalizer.new(entry)
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should omit the cover image when page fetch fails with HTTP error" do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_return(status: 503)

    entry = feed_entry(0)

    post = stub_dns { Normalizer::ElementyNormalizer.new(entry).normalize }

    assert_empty post.attachment_urls
  end

  test "#normalize should omit the cover image on network error" do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)

    post = stub_dns { Normalizer::ElementyNormalizer.new(entry).normalize }

    assert_empty post.attachment_urls
  end

  test "#normalize should report via Rails.error when page fetched but .ill_block img is missing" do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_return(status: 200, body: "<html><body><p>no image here</p></body></html>")

    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      post = stub_dns { Normalizer::ElementyNormalizer.new(entry).normalize }
      assert_equal [], post.attachment_urls
    end

    assert_equal 1, reported.size
    assert_match(/elementy.*ill_block img missing/, reported.first.message)
  end

  test "#normalize should omit the cover image when img src is malformed" do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_return(status: 200, body: '<html><body><div class="ill_block"><img src="http://bad uri[here]" /></div></body></html>')

    entry = feed_entry(0)

    post = stub_dns { Normalizer::ElementyNormalizer.new(entry).normalize }

    assert_equal [], post.attachment_urls
  end
end
