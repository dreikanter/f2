require "test_helper"

class Normalizer::TomorrowsNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/tomorrows"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 200, body: file_fixture("feeds/tomorrows/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::TomorrowsNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal "The Black Cube - https://365tomorrows.com/2026/06/10/the-black-cube/", post.content
  end

  test "#normalize should include story text as a comment" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "There was a moment, in his dream"
  end

  test "#normalize should fall back to feed summary when page fetch fails" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Author: Bill Cox"
  end

  test "#normalize should preserve paragraphs and line breaks" do
    post = normalize_story(<<~HTML)
      <p><strong>Author: Bill Cox</strong></p>
      <p>The ship stopped.<br>Silence &amp; darkness.</p>
      <p>Then <em>someone</em> knocked.</p>
    HTML

    assert_equal ["Author: Bill Cox\n\nThe ship stopped.\nSilence & darkness.\n\nThen someone knocked."], post.comments
  end

  test "#normalize should retain a story that fits one full comment" do
    story = "A" * Post::MAX_COMMENT_LENGTH

    post = normalize_story("<p>#{story}</p>")

    assert_equal [story], post.comments
  end

  test "#normalize should split at paragraph boundaries without losing text" do
    first = "The ship drifted through the dark. " * 60
    second = "Nobody answered the radio. " * 60

    post = normalize_story("<p>#{first}</p><p>#{second}</p>")

    assert_equal [first.strip, second.strip], post.comments
  end

  test "#normalize should split an oversized paragraph at a sentence boundary" do
    first = "The ship drifted through the dark. " * 60
    second = "Nobody answered " * 80 + "the radio."

    post = normalize_story("<p>#{first}#{second}</p>")

    assert_equal [first.strip, second], post.comments
  end

  test "#normalize should keep closing quotes with their sentence" do
    first = "He said, “We are alone.” " * 80
    second = "Nobody answered " * 100 + "the radio."

    post = normalize_story("<p>#{first}#{second}</p>")

    assert_equal [first.strip, second], post.comments
  end

  test "#normalize should split at line breaks before splitting sentences" do
    first = "The ship drifted through the dark. " * 60
    second = "Nobody answered the radio. " * 60

    post = normalize_story("<p>#{first}<br>#{second}</p>")

    assert_equal [first.strip, second.strip], post.comments
  end

  test "#normalize should split a long sentence at a word boundary" do
    first = ("silence " * 375).strip
    second = "until someone knocked."

    post = normalize_story("<p>#{first} #{second}</p>")

    assert_equal [first, second], post.comments
  end

  test "#normalize should split unbroken text within the comment limit" do
    first = "Ж" * Post::MAX_COMMENT_LENGTH

    post = normalize_story("<p>#{first}end</p>")

    assert_equal [first, "end"], post.comments
  end

  test "#normalize should retain exactly four full comments without truncation" do
    paragraph = "Ж" * Post::MAX_COMMENT_LENGTH

    post = normalize_story("<p>#{paragraph}</p>" * 4)

    assert_equal [paragraph, paragraph, paragraph, paragraph], post.comments
  end

  test "#normalize should truncate stories beyond four comments" do
    paragraph = "Ж" * Post::MAX_COMMENT_LENGTH

    post = normalize_story("<p>#{paragraph}</p>" * 5)

    assert_equal [paragraph, paragraph, paragraph, "#{paragraph[0...-1]}…"], post.comments
  end

  test "#normalize should preserve breaks and split long RSS fallback content" do
    first = "The ship drifted through the dark. " * 60
    second = "Nobody answered the radio. " * 60
    entry = feed_entry(0)
    entry.raw_data["content"] = "<p>#{first}</p><p>#{second}<br>Then someone knocked.</p>"
    stub_request(:get, entry.raw_data["link"]).to_return(status: 503)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal [first.strip, "#{second.strip}\nThen someone knocked."], post.comments
  end

  test "#normalize should omit comments for an empty story" do
    post = normalize_story("<p> </p>")

    assert_empty post.comments
  end

  test "#normalize should report via Rails.error when page fetched but .entry-content missing" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 200, body: "<html><body><p>no entry-content here</p></body></html>")

    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      Normalizer::TomorrowsNormalizer.new(entry).normalize
    end

    assert reported.any? { |e| e.message.include?(".entry-content missing") },
           "expected Rails.error.report for missing .entry-content"
  end

  test "#normalize should not report via Rails.error on transient page fetch failure" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      Normalizer::TomorrowsNormalizer.new(entry).normalize
    end

    assert_empty reported, "should not report transient HTTP failures to Rails.error"
  end

  private

  def normalize_story(html)
    entry = feed_entry(0)
    stub_request(:get, entry.raw_data["link"])
      .to_return(status: 200, body: "<div class='entry-content'>#{html}</div>")

    Normalizer::TomorrowsNormalizer.new(entry).normalize
  end
end
