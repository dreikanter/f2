require "test_helper"

class Normalizer::SavagechickensNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/savagechickens"
  end

  def processor_class
    Processor::RssProcessor
  end

  def normalize(index)
    Normalizer::SavagechickensNormalizer.new(feed_entry(index)).normalize
  end

  test "#normalize should match the expected normalization result" do
    assert_matches_snapshot(normalize(0).normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the title as content" do
    assert_equal "Sample Sample Sample - https://www.savagechickens.com/2026/09/sample-sample.html", normalize(0).content
  end

  test "#normalize should put the caption in the first comment" do
    assert_equal ["Sample caption one."], normalize(0).comments
  end

  test "#normalize should attach the cartoon" do
    post = normalize(0)

    assert_equal ["https://www.savagechickens.com/wp-content/uploads/sample-one.jpg"], post.attachment_urls
  end

  test "#normalize should split a multi-paragraph caption into separate comments" do
    post = normalize(2)

    assert_equal 2, post.comments.size
    assert_match(/Sample first paragraph/, post.comments.first)
    assert_match(/Sample second paragraph/, post.comments.second)
  end

  # The description is a truncated excerpt once a post runs long, so the
  # caption has to come from content:encoded.
  test "#normalize should not take the caption from the truncated excerpt" do
    assert_no_match(/…/, normalize(2).comments.first)
  end

  test "#normalize should keep emoji out of the attachments" do
    post = normalize(2)

    assert_equal ["https://www.savagechickens.com/wp-content/uploads/sample-three.jpg"], post.attachment_urls
    assert_match(/🙂/, post.comments.first)
  end

  test "#normalize should fall back to the description when content is missing" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Sample Entry Four",
      "summary" => "Sample caption four.",
      "link" => "https://www.savagechickens.com/2026/08/sample-four.html"
    })

    post = Normalizer::SavagechickensNormalizer.new(entry).normalize

    assert_equal ["Sample caption four."], post.comments
  end

  test "#normalize should leave comments empty for a caption-less entry" do
    entry = create(:feed_entry, raw_data: {
      "title" => "Sample Entry Five",
      "content" => '<p><img src="https://www.savagechickens.com/wp-content/uploads/sample-five.jpg" /></p>',
      "link" => "https://www.savagechickens.com/2026/08/sample-five.html"
    })

    post = Normalizer::SavagechickensNormalizer.new(entry).normalize

    assert_equal [], post.comments
    assert_equal "Sample Entry Five - https://www.savagechickens.com/2026/08/sample-five.html", post.content
  end
end
