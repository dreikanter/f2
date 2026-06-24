require "test_helper"

class FeedProfileDetectorTest < ActiveSupport::TestCase
  def rss_feed_body
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
        </channel>
      </rss>
    XML
  end

  test ".call should return DetectionResult with the InputClassifier shape" do
    result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
    assert_equal :url, result.input_shape
  end

  test ".call should return empty candidates for malformed input" do
    result = FeedProfileDetector.call(input: "")
    assert_equal :malformed, result.input_shape
    assert_empty result.candidates
  end

  test ".call should fall back to AI extraction when no non-AI matcher fires for a URL" do
    result = FeedProfileDetector.call(input: "https://example.com/page", fetched_body: "<html><body/></html>")
    assert_equal :url, result.input_shape
    assert_equal ["llm_website_extractor"], result.candidates.map(&:profile_key)
    assert_equal :ai_fallback, result.candidates.first.rank_reason
  end

  test ".call should rank a generic RSS feed above the AI fallback" do
    result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
    assert_equal ["rss", "llm_website_extractor"], result.candidates.map(&:profile_key)

    rss = result.candidates.first
    assert_equal 0, rss.rank
    assert_equal false, rss.depends_on_ai
    assert_equal :specific_match, rss.rank_reason
  end

  test ".call should rank specific matchers above generic ones, with AI fallback last" do
    result = FeedProfileDetector.call(input: "https://xkcd.com/rss.xml", fetched_body: rss_feed_body)

    profile_keys = result.candidates.map(&:profile_key)
    assert_equal %w[xkcd rss llm_website_extractor], profile_keys, "xkcd (100) > rss (10) > AI (1)"

    xkcd, rss, ai = result.candidates
    assert_equal 0, xkcd.rank
    assert_equal 1, rss.rank
    assert_equal 2, ai.rank
    assert_equal :specific_match, xkcd.rank_reason
    assert_equal :generic_match, rss.rank_reason
    assert_equal :ai_fallback, ai.rank_reason
  end

  test ".call should place AI-backed candidates after non-AI candidates" do
    matchers = [ProfileMatcher::RssProfileMatcher, ai_matcher_class(specificity: 1000)]

    FeedProfile.stub(:matchers_for, ->(_) { matchers }) do
      result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)

      assert_equal "rss", result.candidates.first.profile_key, "non-AI ranks above AI even when AI is more specific"
      assert_equal "fake_ai", result.candidates.last.profile_key
      assert_equal :specific_match, result.candidates.first.rank_reason
      assert_equal :ai_fallback, result.candidates.last.rank_reason
    end
  end

  test ".call should use registration order as the tiebreaker" do
    tie_matcher = build_matcher_class("FakeTieProfileMatcher", specificity: 10)
    matchers = [ProfileMatcher::RssProfileMatcher, tie_matcher]

    FeedProfile.stub(:matchers_for, ->(_) { matchers }) do
      result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
      assert_equal "rss", result.candidates.first.profile_key, "rss registered first wins the tie"
    end
  end

  test ".call should be deterministic across repeated invocations" do
    result_a = FeedProfileDetector.call(input: "https://xkcd.com/rss.xml", fetched_body: rss_feed_body)
    result_b = FeedProfileDetector.call(input: "https://xkcd.com/rss.xml", fetched_body: rss_feed_body)
    assert_equal result_a.candidates.map(&:profile_key), result_b.candidates.map(&:profile_key)
  end

  test ".call should skip a matcher that raises and continue the chain" do
    bomb = build_matcher_class("BombProfileMatcher", specificity: 50) do
      def match?
        raise StandardError, "kaboom"
      end
    end
    matchers = [bomb, ProfileMatcher::RssProfileMatcher]

    reported = []
    Rails.error.stub(:report, ->(err, **kwargs) { reported << [err.message, kwargs] }) do
      FeedProfile.stub(:matchers_for, ->(_) { matchers }) do
        result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
        assert_includes result.candidates.map(&:profile_key), "rss", "rss still matches even though bomb raised"
      end
    end

    assert reported.any? { |msg, _| msg == "kaboom" }, "expected Rails.error.report to capture the matcher failure"
  end

  test ".call should report title-extraction failures via Rails.error and return nil for the title" do
    boom_extractor = Class.new do
      def initialize(_input, _response); end
      def title
        raise StandardError, "title boom"
      end
    end

    reported = []
    FeedProfile.stub(:title_extractor_class_for, ->(_key) { boom_extractor }) do
      Rails.error.stub(:report, ->(err, **kwargs) { reported << [err.message, kwargs] }) do
        result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
        assert_nil result.candidates.first.title, "title should be nil when extractor raises"
      end
    end

    assert reported.any? { |msg, kwargs| msg == "title boom" && kwargs.dig(:context, :source) == "title_extraction" },
           "expected Rails.error.report to capture the title-extraction failure"
  end

  test ".call should set and clear Thread.current[:llm_detection_phase]" do
    captured_flag = nil
    spy = build_matcher_class("SpyProfileMatcher", specificity: 1) do
      define_method(:match?) do
        captured_flag = Thread.current[:llm_detection_phase]
        false
      end
    end

    FeedProfile.stub(:matchers_for, ->(_) { [spy] }) do
      FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: "")
    end

    assert_equal true, captured_flag, "flag should be set while matchers run"
    assert_nil Thread.current[:llm_detection_phase], "flag must be cleared after call"
  end

  # Guards the shape persisted to FeedIdentification#candidates: Rails'
  # native Data#as_json must keep yielding string keys with rank_reason
  # stringified, so a future field/type change can't silently break it.
  test "DetectionCandidate should serialize to the persisted candidate hash" do
    candidate = FeedProfileDetector::DetectionCandidate.new(
      profile_key: "rss",
      title: "Example Blog",
      depends_on_ai: false,
      rank: 0,
      rank_reason: :specific_match
    )

    assert_equal(
      {
        "profile_key" => "rss",
        "title" => "Example Blog",
        "depends_on_ai" => false,
        "rank" => 0,
        "rank_reason" => "specific_match"
      },
      candidate.as_json
    )
  end

  private

  def build_matcher_class(class_name, specificity:, &block)
    Class.new(ProfileMatcher::Base) do
      const_set(:NAME_OVERRIDE, "ProfileMatcher::#{class_name}")
      define_singleton_method(:name) { const_get(:NAME_OVERRIDE) }
      input_shape :url
      match_specificity specificity
      depends_on_ai false

      def match?
        true
      end

      class_eval(&block) if block
    end
  end

  def ai_matcher_class(specificity:)
    Class.new(ProfileMatcher::Base) do
      define_singleton_method(:name) { "ProfileMatcher::FakeAiProfileMatcher" }
      input_shape :url
      match_specificity specificity
      depends_on_ai true

      def match?
        true
      end
    end
  end
end
