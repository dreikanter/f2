require "test_helper"

class FeedProfileTest < ActiveSupport::TestCase
  test ".all returns list of profile keys" do
    expected = [
      "aerostat",
      "bluesky",
      "buni",
      "elementy",
      "json_feed",
      "litterbox",
      "llm",
      "lobsters",
      "melodymae",
      "monkeyuser",
      "nextbigfuture",
      "oglaf",
      "pluralistic",
      "reddit",
      "rss",
      "smbc",
      "telegram",
      "theycantalk",
      "tomorrows",
      "twitter",
      "webhook",
      "xkcd",
      "youtube"
    ]

    assert_equal expected, FeedProfile.all.sort
  end

  test ".push? should return true only for push-ingested profiles" do
    assert FeedProfile.push?("webhook")
    assert_not FeedProfile.push?("rss")
    assert_not FeedProfile.push?("llm")
    assert_not FeedProfile.push?(nil)
  end

  test "webhook profile resolves only its normalizer stage" do
    assert_equal "Normalizer::WebhookNormalizer", FeedProfile.normalizer_class_for("webhook").name
    assert_raises(ArgumentError) { FeedProfile.loader_class_for("webhook") }
    assert_raises(ArgumentError) { FeedProfile.processor_class_for("webhook") }
  end

  test "webhook profile accepts only empty params" do
    schema = FeedProfile.parameter_schema_for("webhook")

    assert JSONSchemer.schema(schema).valid?({})
    assert_not JSONSchemer.schema(schema).valid?({ "url" => "https://example.com" })
  end

  test ".source_key_for should return nil for an input-less profile" do
    assert_nil FeedProfile.source_key_for("webhook")
    assert_equal "url", FeedProfile.source_key_for("rss")
    assert_equal "prompt", FeedProfile.source_key_for("llm")
  end

  test ".source_input_for should ignore a smuggled url key on an input-less profile" do
    assert_nil FeedProfile.source_input_for("webhook", { "url" => "https://example.com" })
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
      assert_includes %i[url query any none], entry[:input_shape], "#{key}: input_shape"
      assert_includes [true, false], entry[:depends_on_ai], "#{key}: depends_on_ai"
      assert_includes [true, false], entry[:scheduled], "#{key}: scheduled"
      if entry[:depends_on_ai] || entry[:push]
        # AI and push profiles are structurally excluded from detection
        # (spec 005 §7, spec 006 §1): no matcher.
        assert_nil entry[:matcher], "#{key}: AI/push profile must not register a matcher"
      else
        assert_kind_of String, entry[:matcher], "#{key}: matcher"
      end
      assert_kind_of Hash, entry[:parameter_schema], "#{key}: parameter_schema"

      if entry[:push]
        # Push profiles have nothing to fetch (spec 006 §1): no loader/processor.
        assert_nil entry[:loader], "#{key}: push profile must not register a loader"
        assert_nil entry[:processor], "#{key}: push profile must not register a processor"
      else
        assert_kind_of Hash, entry[:loader], "#{key}: loader entry must be a hash"
        assert_kind_of String, entry[:loader][:class], "#{key}: loader.class"
        assert_kind_of Hash, entry[:loader][:config], "#{key}: loader.config"

        assert_kind_of Hash, entry[:processor], "#{key}: processor entry must be a hash"
        assert_kind_of String, entry[:processor][:class], "#{key}: processor.class"
        assert_kind_of Hash, entry[:processor][:config], "#{key}: processor.config"
      end

      assert_kind_of Hash, entry[:normalizer], "#{key}: normalizer entry must be a hash"
      assert_kind_of String, entry[:normalizer][:class], "#{key}: normalizer.class"
      assert_kind_of Hash, entry[:normalizer][:config], "#{key}: normalizer.config"

      if entry[:depends_on_ai]
        # AI profiles declare the universal-post output_schema on the loader
        # stage that calls the LLM.
        assert_kind_of Hash, entry[:loader][:config][:output_schema], "#{key}: output_schema required for AI profile"
      end
    end
  end

  test "every matcher-bearing PROFILES entry has a resolvable matcher class" do
    FeedProfile::PROFILES.each do |key, entry|
      next if entry[:matcher].blank?

      matcher_class = entry[:matcher].constantize
      assert matcher_class < ProfileMatcher::Base, "#{key}: matcher must subclass ProfileMatcher::Base"
    end
  end

  test "all pull PROFILES have resolvable loader classes" do
    FeedProfile::PROFILES.each_key do |key|
      next if FeedProfile.push?(key)

      loader_class = FeedProfile.loader_class_for(key)
      assert loader_class.present?, "Profile '#{key}' should have a resolvable loader class"
      assert loader_class < Loader::Base, "Profile '#{key}' loader should inherit from Loader::Base"
    end
  end

  test "all pull PROFILES have resolvable processor classes" do
    FeedProfile::PROFILES.each_key do |key|
      next if FeedProfile.push?(key)

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

  test "all non-AI pull PROFILES have resolvable title extractor classes" do
    # AI-backed profiles emit the universal post shape directly, and push
    # profiles never go through identification, so both skip the
    # title-extractor stage.
    FeedProfile::PROFILES.each do |key, entry|
      next if entry[:depends_on_ai] || entry[:push]

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

  test ".matchers returns matcher classes in registration order" do
    matchers = FeedProfile.matchers

    rss_index = matchers.index(ProfileMatcher::RssProfileMatcher)
    xkcd_index = matchers.index(ProfileMatcher::XkcdProfileMatcher)

    assert_not_nil rss_index
    assert_not_nil xkcd_index
    assert rss_index < xkcd_index, "rss should come before xkcd in registration order"
  end

  test ".matchers never includes the AI profile (structural exclusion)" do
    # The AI profile registers no matcher, so detection can't select it (spec §7)
    # — it's reachable only via Mode B, never by auto-detection.
    keys = FeedProfile.matchers.map(&:profile_key)
    assert_not_includes keys, "llm"
  end

  test ".matchers returns every matcher-bearing profile" do
    matcher_bearing = FeedProfile::PROFILES.count { |_key, entry| entry[:matcher].present? }
    assert_equal matcher_bearing, FeedProfile.matchers.size
  end

  test ".depends_on_ai? returns true for AI-backed profiles" do
    assert FeedProfile.depends_on_ai?("llm")
    assert_not FeedProfile.depends_on_ai?("rss")
    assert_not FeedProfile.depends_on_ai?("xkcd")
    assert_not FeedProfile.depends_on_ai?("nonexistent")
  end

  test ".scheduled? returns the explicit scheduling capability" do
    assert FeedProfile.scheduled?("rss")
    assert FeedProfile.scheduled?("llm")
    assert_not FeedProfile.scheduled?("nonexistent")
    assert_not FeedProfile.scheduled?(nil)
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

  test "UNIVERSAL_OUTPUT_SCHEMA should accept a null source_url and no uid, but require the key" do
    schemer = JSONSchemer.schema(FeedProfile::UNIVERSAL_OUTPUT_SCHEMA)

    assert schemer.valid?({ "items" => [{ "body" => "roundup", "source_url" => nil }] }), "digest item (null source_url, no uid)"
    assert schemer.valid?({ "items" => [{ "body" => "x", "source_url" => "https://e.com/a" }] }), "feed-style item"
    assert schemer.valid?({ "items" => [{ "uid" => "z", "body" => "x", "source_url" => nil }] }), "a stray uid is tolerated"
    assert_not schemer.valid?({ "items" => [{ "body" => "x" }] }), "a missing source_url key is malformed, not a digest"
  end
end
