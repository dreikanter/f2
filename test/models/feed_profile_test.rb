require "test_helper"

class FeedProfileTest < ActiveSupport::TestCase
  test "all returns list of profile keys" do
    assert_equal ["rss", "xkcd"], FeedProfile.all.sort
  end

  test "exists? returns true for valid profile key" do
    assert FeedProfile.exists?("rss")
    assert FeedProfile.exists?("xkcd")
  end

  test "exists? returns false for invalid profile key" do
    assert_not FeedProfile.exists?("invalid")
    assert_not FeedProfile.exists?(nil)
  end

  test "all PROFILES have resolvable loader classes" do
    FeedProfile::PROFILES.each do |key, config|
      profile = FeedProfile.new(key)
      assert profile.loader_class.present?, "Profile '#{key}' should have a resolvable loader class"
      assert profile.loader_class < Loader::Base, "Profile '#{key}' loader should inherit from Loader::Base"
    end
  end

  test "all PROFILES have resolvable processor classes" do
    FeedProfile::PROFILES.each do |key, config|
      profile = FeedProfile.new(key)
      assert profile.processor_class.present?, "Profile '#{key}' should have a resolvable processor class"
      assert profile.processor_class < Processor::Base, "Profile '#{key}' processor should inherit from Processor::Base"
    end
  end

  test "all PROFILES have resolvable normalizer classes" do
    FeedProfile::PROFILES.each do |key, config|
      profile = FeedProfile.new(key)
      assert profile.normalizer_class.present?, "Profile '#{key}' should have a resolvable normalizer class"
      assert profile.normalizer_class < Normalizer::Base, "Profile '#{key}' normalizer should inherit from Normalizer::Base"
    end
  end

  test "valid? returns true for valid profile key" do
    profile = FeedProfile.new("rss")
    assert profile.valid?
  end

  test "valid? returns false for invalid profile key" do
    profile = FeedProfile.new("invalid")
    assert_not profile.valid?
  end

  test "loader_class returns nil for invalid profile" do
    profile = FeedProfile.new("invalid")
    assert_nil profile.loader_class
  end

  test "processor_class returns nil for invalid profile" do
    profile = FeedProfile.new("invalid")
    assert_nil profile.processor_class
  end

  test "normalizer_class returns nil for invalid profile" do
    profile = FeedProfile.new("invalid")
    assert_nil profile.normalizer_class
  end

  test "display_name returns translated name" do
    profile = FeedProfile.new("rss")
    assert_equal "RSS Feed", profile.display_name
  end

  test "display_name returns translated name for xkcd" do
    profile = FeedProfile.new("xkcd")
    assert_equal "XKCD Comics", profile.display_name
  end
end
