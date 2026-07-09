require "test_helper"

class ProfileMatcher::YoutubeProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::YoutubeProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::YoutubeProfileMatcher.match_specificity
  end

  test "#match? should match youtube.com with www prefix" do
    assert matcher("https://www.youtube.com/@SomeChannel").match?
    assert matcher("https://www.youtube.com/channel/UC123").match?
    assert matcher("https://www.youtube.com/c/ChannelName").match?
    assert matcher("https://www.youtube.com/user/Username").match?
    assert matcher("https://www.youtube.com/feeds/videos.xml?channel_id=UC123").match?
  end

  test "#match? should match youtube.com without www prefix" do
    assert matcher("https://youtube.com/@SomeChannel").match?
    assert matcher("https://youtube.com/feeds/videos.xml?channel_id=UC123").match?
  end

  test "#match? should match youtu.be with and without www prefix" do
    assert matcher("https://youtu.be/dQw4w9WgXcQ").match?
    assert matcher("https://www.youtu.be/dQw4w9WgXcQ").match?
  end

  test "#match? should not match non-YouTube URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
    assert_not matcher("https://vimeo.com/channel/test").match?
  end

  test "#match? should not match domains that merely end with youtube.com" do
    assert_not matcher("https://notyoutube.com/feed").match?
    assert_not matcher("https://fakeyoutube.com/channel/UC123").match?
  end

  test "#match? should not match URLs that contain youtube in the path only" do
    assert_not matcher("https://example.com/youtube.com/feed").match?
  end

  test "#match? should handle blank input" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
