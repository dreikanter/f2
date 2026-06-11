require "test_helper"

class Normalizer::ElementyNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

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
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::ElementyNormalizer.new(entry).normalize

    assert_includes post.content, "Генетики выяснили происхождение первых лошадей"
  end

  test "#normalize should extract a cover image from the article page" do
    entry = feed_entry(0)

    post = Normalizer::ElementyNormalizer.new(entry).normalize

    assert_equal ["https://elementy.ru/images/news/2025/horses_migration.jpg"], post.attachment_urls
  end

  test "#normalize should include stripped summary as a comment" do
    entry = feed_entry(0)

    post = Normalizer::ElementyNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Международная группа исследователей"
  end

  test "#normalize should return empty attachments when page fetch fails" do
    stub_request(:get, "https://elementy.ru/novosti_nauki/434641/Genetiki_vyyasnili_proiskhozhdenie_pervykh_loshadey_v_Zapadnoy_Evrope")
      .to_return(status: 503)

    entry = feed_entry(0)

    post = Normalizer::ElementyNormalizer.new(entry).normalize

    assert_equal [], post.attachment_urls
  end
end
