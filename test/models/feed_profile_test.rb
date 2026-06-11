require "test_helper"

class FeedProfileTest < ActiveSupport::TestCase
  test ".all returns list of profile keys" do
    assert_equal ["llm_web_search", "llm_website_extractor", "oglaf", "reddit", "rss", "telegram", "twitter", "xkcd", "youtube"], FeedProfile.all.sort
  end

  test ".exists? returns true for valid profile key" do
    assert FeedProfile.exists?("rss")
    assert FeedProfile.exists?("xkcd")
  end

  test ".exists? returns false for invalid profile key" do
    assert_not FeedProfile.exists?("invalid")
    assert_not FeedProfile.exists?(nil)
  end

  test ".[] returns the full registry entry hash" do
    entry = FeedProfile["rss"]

    assert_kind_of Hash, entry
    assert_equal "RSS Feed", entry[:display_name]
    assert_equal :url, entry[:input_shape]
    assert_equal "ProfileMatcher::RssProfileMatcher", entry[:matcher]
    assert_kind_of Hash, entry[:loader]
  end

  test ".[] returns nil for unknown key" do
    assert_nil FeedProfile["nope"]
  end

  test "every PROFILES entry conforms to the enriched shape" do
    FeedProfile::PROFILES.each do |key, entry|
      assert_kind_of String, entry[:display_name], "#{key}: display_name"
      assert_kind_of String, entry[:description], "#{key}: description"
      assert_includes %i[url query any], entry[:input_shape], "#{key}: input_shape"
      assert_includes [true, false], entry[:depends_on_ai], "#{key}: depends_on_ai"
      assert_kind_of String, entry[:matcher], "#{key}: matcher"
      assert_kind_of Hash, entry[:parameter_schema], "#{key}: parameter_schema"

      assert_kind_of Hash, entry[:loader], "#{key}: loader entry must be a hash"
      assert_kind_of String, entry[:loader][:class], "#{key}: loader.class"
      assert_kind_of Hash, entry[:loader][:config], "#{key}: loader.config"

      assert_kind_of Hash, entry[:processor], "#{key}: processor entry must be a hash"
      assert_kind_of String, entry[:processor][:class], "#{key}: processor.class"
      assert_kind_of Hash, entry[:processor][:config], "#{key}: processor.config"

      assert_kind_of Hash, entry[:normalizer], "#{key}: normalizer entry must be a hash"
      assert_kind_of String, entry[:normalizer][:class], "#{key}: normalizer.class"
      assert_kind_of Hash, entry[:normalizer][:config], "#{key}: normalizer.config"

      if entry[:depends_on_ai]
        # AI profiles declare the universal-post output_schema at the
        # top level or on the loader stage that calls the LLM.
        schema = entry[:loader][:config][:output_schema] || entry[:output_schema]
        assert_kind_of Hash, schema, "#{key}: output_schema required for AI profile"
      end
    end
  end

  test "every PROFILES entry has a resolvable matcher class" do
    FeedProfile::PROFILES.each do |key, entry|
      matcher_class = entry[:matcher].constantize
      assert matcher_class < ProfileMatcher::Base, "#{key}: matcher must subclass ProfileMatcher::Base"
    end
  end

  test "all PROFILES have resolvable loader classes" do
    FeedProfile::PROFILES.each_key do |key|
      loader_class = FeedProfile.loader_class_for(key)
      assert loader_class.present?, "Profile '#{key}' should have a resolvable loader class"
      assert loader_class < Loader::Base, "Profile '#{key}' loader should inherit from Loader::Base"
    end
  end

  test "all PROFILES have resolvable processor classes" do
    FeedProfile::PROFILES.each_key do |key|
      processor_class = FeedProfile.processor_class_for(key)
      assert processor_class.present?, "Profile '#{key}' should have a resolvable processor class"
      assert processor_class < Processor::Base, "Profile '#{key}' processor should inherit from Processor::Base"
    end
  end

  test "all PROFILES have resolvable normalizer classes" do
    FeedProfile::PROFILES.each_key do |key|
      normalizer_class = FeedProfile.normalizer_class_for(key)
      assert normalizer_class.present?, "Profile '#{key}' should have a resolvable normalizer class"
      assert normalizer_class < Normalizer::Base, "Profile '#{key}' normalizer should inherit from Normalizer::Base"
    end
  end

  test "all non-AI PROFILES have resolvable title extractor classes" do
    # AI-backed profiles emit the universal post shape directly, so they
    # skip the title-extractor stage.
    FeedProfile::PROFILES.each do |key, entry|
      next if entry[:depends_on_ai]

      title_extractor_class = FeedProfile.title_extractor_class_for(key)
      assert title_extractor_class.present?, "Profile '#{key}' should have a resolvable title extractor class"
      assert title_extractor_class < TitleExtractor::Base, "Profile '#{key}' title extractor should inherit from TitleExtractor::Base"
    end
  end

  test "class_for methods raise ArgumentError for invalid keys" do
    assert_raises(ArgumentError) { FeedProfile.loader_class_for("invalid") }
    assert_raises(ArgumentError) { FeedProfile.processor_class_for("invalid") }
    assert_raises(ArgumentError) { FeedProfile.normalizer_class_for("invalid") }
    assert_raises(ArgumentError) { FeedProfile.title_extractor_class_for("invalid") }
  end

  test ".config_for returns the stage config hash" do
    assert_equal({}, FeedProfile.config_for("rss", :loader))
  end

  test ".config_for raises ArgumentError for invalid keys" do
    assert_raises(ArgumentError) { FeedProfile.config_for("invalid", :loader) }
  end

  test ".matchers_for returns matcher classes for a given input_shape" do
    matchers = FeedProfile.matchers_for(:url)

    assert_includes matchers, ProfileMatcher::RssProfileMatcher
    assert_includes matchers, ProfileMatcher::XkcdProfileMatcher
  end

  test ".matchers_for returns matchers in registration order" do
    matchers = FeedProfile.matchers_for(:url)

    rss_index = matchers.index(ProfileMatcher::RssProfileMatcher)
    xkcd_index = matchers.index(ProfileMatcher::XkcdProfileMatcher)

    assert rss_index < xkcd_index, "rss should come before xkcd in registration order"
  end

  test ".matchers_for returns the query matcher for the query shape" do
    assert_includes FeedProfile.matchers_for(:query), ProfileMatcher::LlmWebSearchMatcher
  end

  test ".matchers_for returns every matcher when input_shape is nil or :any" do
    every = FeedProfile.matchers_for(nil)

    assert_equal FeedProfile::PROFILES.size, every.size
    assert_equal every, FeedProfile.matchers_for(:any)
  end

  test ".depends_on_ai? returns true for AI-backed profiles" do
    assert FeedProfile.depends_on_ai?("llm_website_extractor")
    assert_not FeedProfile.depends_on_ai?("rss")
    assert_not FeedProfile.depends_on_ai?("xkcd")
    assert_not FeedProfile.depends_on_ai?("nonexistent")
  end

  test ".parameter_schema_for returns the schema for a profile" do
    schema = FeedProfile.parameter_schema_for("rss")

    assert_kind_of Hash, schema
    assert_equal "object", schema["type"]
    assert_equal ["url"], schema["required"]
  end

  test ".parameter_schema_for returns nil for unknown profiles" do
    assert_nil FeedProfile.parameter_schema_for("nope")
  end

  test "#display_name_for should return RSS Feed for rss profile" do
    assert_equal "RSS Feed", FeedProfile.display_name_for("rss")
  end

  test "#display_name_for should return XKCD for xkcd profile" do
    assert_equal "XKCD", FeedProfile.display_name_for("xkcd")
  end

  test "#display_name_for should titleize unknown profile keys" do
    assert_equal "Custom Profile", FeedProfile.display_name_for("custom_profile")
  end
end
