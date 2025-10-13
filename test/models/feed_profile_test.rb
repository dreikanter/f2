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

  test "loader_class_for returns Loader::HttpLoader for rss profile" do
    assert_equal Loader::HttpLoader, FeedProfile.loader_class_for("rss")
  end

  test "processor_class_for returns Processor::RssProcessor for rss profile" do
    assert_equal Processor::RssProcessor, FeedProfile.processor_class_for("rss")
  end

  test "normalizer_class_for returns Normalizer::RssNormalizer for rss profile" do
    assert_equal Normalizer::RssNormalizer, FeedProfile.normalizer_class_for("rss")
  end

  test "all PROFILES have resolvable title extractor classes" do
    FeedProfile::PROFILES.each do |key, config|
      title_extractor_class = FeedProfile.title_extractor_class_for(key)
      assert title_extractor_class.present?, "Profile '#{key}' should have a resolvable title extractor class"
      assert title_extractor_class < TitleExtractor::Base, "Profile '#{key}' title extractor should inherit from TitleExtractor::Base"
    end
  end

  test "title_extractor_class_for raises ArgumentError for invalid key" do
    assert_raises(ArgumentError) { FeedProfile.title_extractor_class_for("invalid") }
  end

  test "title_extractor_class_for raises ArgumentError for nil key" do
    assert_raises(ArgumentError) { FeedProfile.title_extractor_class_for(nil) }
  end

  test "title_extractor_class_for returns TitleExtractor::RssTitleExtractor for rss profile" do
    assert_equal TitleExtractor::RssTitleExtractor, FeedProfile.title_extractor_class_for("rss")
  end

  test "title_extractor_class_for returns TitleExtractor::RssTitleExtractor for xkcd profile" do
    assert_equal TitleExtractor::RssTitleExtractor, FeedProfile.title_extractor_class_for("xkcd")
  end
end
