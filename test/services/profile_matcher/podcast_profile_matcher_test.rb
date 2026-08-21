require "test_helper"

class ProfileMatcher::PodcastProfileMatcherTest < ActiveSupport::TestCase
  def matcher(body)
    ProfileMatcher::PodcastProfileMatcher.new("https://example.com/feed.xml", body)
  end

  test ".match_specificity should be 15, above generic RSS" do
    assert_equal 15, ProfileMatcher::PodcastProfileMatcher.match_specificity
    assert_operator ProfileMatcher::PodcastProfileMatcher.match_specificity, :>,
                    ProfileMatcher::RssProfileMatcher.match_specificity
  end

  test ".profile_key should be podcast" do
    assert_equal "podcast", ProfileMatcher::PodcastProfileMatcher.profile_key
  end

  test "#match? should match an RSS feed declaring the itunes namespace" do
    body = file_fixture("feeds/podcast/feed.xml").read

    assert matcher(body).match?
  end

  test "#match? should match a single-quoted namespace declaration" do
    body = "<rss xmlns:itunes='http://www.itunes.com/dtds/podcast-1.0.dtd' version=\"2.0\"><channel></channel></rss>"

    assert matcher(body).match?
  end

  test "#match? should not match plain RSS without the itunes namespace" do
    body = file_fixture("feeds/rss/feed.xml").read

    assert_not matcher(body).match?
  end

  test "#match? should not match an Atom feed with an itunes declaration" do
    # Feedjira parses Atom documents with its Atom parser, so the podcast
    # profile must not claim them even when the namespace is declared.
    body = '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"></feed>'

    assert_not matcher(body).match?
  end

  test "#match? should not match when the namespace appears only inside CDATA" do
    body = <<~XML
      <rss version="2.0"><channel><item>
        <description><![CDATA[xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"]]></description>
      </item></channel></rss>
    XML

    assert_not matcher(body).match?
  end

  test "#match? should handle blank inputs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
