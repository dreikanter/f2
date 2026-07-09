require "test_helper"

class ProfileMatcher::TelegramProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::TelegramProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::TelegramProfileMatcher.match_specificity
  end

  test ".profile_key should be telegram" do
    assert_equal "telegram", ProfileMatcher::TelegramProfileMatcher.profile_key
  end

  test "#match? should match a t.me channel URL" do
    assert matcher("https://t.me/examplechannel").match?
  end

  test "#match? should match a t.me/s preview URL" do
    assert matcher("https://t.me/s/examplechannel").match?
  end

  test "#match? should match a telegram.me URL" do
    assert matcher("https://telegram.me/examplechannel").match?
  end

  test "#match? should not match invite links" do
    assert_not matcher("https://t.me/joinchat/AAAAAEHbZ").match?
    assert_not matcher("https://t.me/+AbCdEfGh").match?
  end

  test "#match? should not match the t.me root" do
    assert_not matcher("https://t.me/").match?
  end

  test "#match? should not match sticker packs" do
    assert_not matcher("https://t.me/addstickers/AnimatedEmojies").match?
  end

  test "#match? should not match non-telegram URLs" do
    assert_not matcher("https://example.com/examplechannel").match?
  end

  test "#match? should handle blank input" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
