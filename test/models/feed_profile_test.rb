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

  test "initialize raises ArgumentError for invalid profile key" do
    error = assert_raises(ArgumentError) do
      FeedProfile.new("invalid")
    end
    assert_equal "Unknown feed profile: invalid", error.message
  end
end
