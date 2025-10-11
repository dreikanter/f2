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
      loader_class = FeedProfile.loader_class_for(key)
      assert loader_class.present?, "Profile '#{key}' should have a resolvable loader class"
      assert loader_class < Loader::Base, "Profile '#{key}' loader should inherit from Loader::Base"
    end
  end

  test "all PROFILES have resolvable processor classes" do
    FeedProfile::PROFILES.each do |key, config|
      processor_class = FeedProfile.processor_class_for(key)
      assert processor_class.present?, "Profile '#{key}' should have a resolvable processor class"
      assert processor_class < Processor::Base, "Profile '#{key}' processor should inherit from Processor::Base"
    end
  end

  test "all PROFILES have resolvable normalizer classes" do
    FeedProfile::PROFILES.each do |key, config|
      normalizer_class = FeedProfile.normalizer_class_for(key)
      assert normalizer_class.present?, "Profile '#{key}' should have a resolvable normalizer class"
      assert normalizer_class < Normalizer::Base, "Profile '#{key}' normalizer should inherit from Normalizer::Base"
    end
  end

  test "loader_class_for raises ArgumentError for invalid key" do
    assert_raises(ArgumentError) { FeedProfile.loader_class_for("invalid") }
  end

  test "loader_class_for raises ArgumentError for nil key" do
    assert_raises(ArgumentError) { FeedProfile.loader_class_for(nil) }
  end

  test "processor_class_for raises ArgumentError for invalid key" do
    assert_raises(ArgumentError) { FeedProfile.processor_class_for("invalid") }
  end

  test "processor_class_for raises ArgumentError for nil key" do
    assert_raises(ArgumentError) { FeedProfile.processor_class_for(nil) }
  end

  test "normalizer_class_for raises ArgumentError for invalid key" do
    assert_raises(ArgumentError) { FeedProfile.normalizer_class_for("invalid") }
  end

  test "normalizer_class_for raises ArgumentError for nil key" do
    assert_raises(ArgumentError) { FeedProfile.normalizer_class_for(nil) }
  end
end
