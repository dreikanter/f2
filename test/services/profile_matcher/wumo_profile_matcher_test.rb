require "test_helper"

class ProfileMatcher::WumoProfileMatcherTest < ActiveSupport::TestCase
  test "#match? should recognize the Wumo feed and comic pages" do
    %w[https://wumo.com/wumo?view=rss http://www.wumo.com/wumo/2026/09/08].each do |url|
      assert ProfileMatcher::WumoProfileMatcher.new(url).match?
    end
  end

  test "#match? should not claim other strips or unrelated hosts" do
    [nil, "", "https://wumo.com/truthfacts?view=rss", "https://example.com/wumo"].each do |url|
      assert_not ProfileMatcher::WumoProfileMatcher.new(url).match?
    end
  end

  test ".call should prefer the Wumo profile over generic RSS" do
    result = FeedProfileDetector.call(
      input: "https://wumo.com/wumo?view=rss",
      fetched_body: file_fixture("feeds/wumo/current.xml").read
    )

    assert_equal %w[wumo rss], result.candidates.map(&:profile_key)
  end
end
