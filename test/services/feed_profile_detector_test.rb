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

  test ".call should return empty candidates for blank input" do
    assert_empty FeedProfileDetector.call(input: "").candidates
  end

  test ".call should return no candidates when no deterministic matcher fires" do
    # The AI profile registers no matcher, so a page with no standard feed yields
    # nothing — the entry flow offers the AI bridge, detection never selects it.
    result = FeedProfileDetector.call(input: "https://example.com/page", fetched_body: "<html><body/></html>")
    assert_empty result.candidates
  end

  test ".call should detect a generic RSS feed" do
    result = FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: rss_feed_body)
    assert_equal ["rss"], result.candidates.map(&:profile_key)
  end

  test ".call should rank json_feed above rss when a JSON feed contains XML-like markup" do
    # The RSS matcher scans for `<feed`/`<rss` anywhere in the body, so a JSON
    # feed whose item HTML mentions `<feed>` trips it too. json_feed's stricter
    # parse-and-validate match must win the ranking.
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"Feed",' \
           '"items":[{"id":"1","url":"https://example.com/1","content_html":"<p>The <feed> element</p>"}]}'

    result = FeedProfileDetector.call(input: "https://example.com/feed.json", fetched_body: body)
    profile_keys = result.candidates.map(&:profile_key)

    assert_equal "json_feed", profile_keys.first, "json_feed (20) should outrank rss (10)"
    assert_includes profile_keys, "rss"
    assert_operator profile_keys.index("json_feed"), :<, profile_keys.index("rss")
  end

  test ".call should rank specific matchers above generic ones" do
    result = FeedProfileDetector.call(input: "https://xkcd.com/rss.xml", fetched_body: rss_feed_body)

    profile_keys = result.candidates.map(&:profile_key)
    assert_equal %w[xkcd rss], profile_keys, "xkcd (100) > rss (10)"
  end

  test ".call should use registration order as the tiebreaker" do
    tie_matcher = build_matcher_class("FakeTieProfileMatcher", specificity: 10)
    matchers = [ProfileMatcher::RssProfileMatcher, tie_matcher]

    FeedProfile.stub(:matchers, matchers) do
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
      FeedProfile.stub(:matchers, matchers) do
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

    FeedProfile.stub(:matchers, [spy]) do
      FeedProfileDetector.call(input: "https://example.com/feed.xml", fetched_body: "")
    end

    assert_equal true, captured_flag, "flag should be set while matchers run"
    assert_nil Thread.current[:llm_detection_phase], "flag must be cleared after call"
  end

  # Guards the shape persisted to FeedIdentification#candidates: Rails'
  # native Data#as_json must keep yielding string keys, so a future
  # field/type change can't silently break it.
  test "DetectionCandidate should serialize to the persisted candidate hash" do
    candidate = FeedProfileDetector::DetectionCandidate.new(
      profile_key: "rss",
      title: "Example Blog"
    )

    assert_equal({ "profile_key" => "rss", "title" => "Example Blog" }, candidate.as_json)
  end

  private

  def build_matcher_class(class_name, specificity:, &block)
    Class.new(ProfileMatcher::Base) do
      const_set(:NAME_OVERRIDE, "ProfileMatcher::#{class_name}")
      define_singleton_method(:name) { const_get(:NAME_OVERRIDE) }
      match_specificity specificity

      def match?
        true
      end

      class_eval(&block) if block
    end
  end
end
