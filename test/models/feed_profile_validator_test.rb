require "test_helper"

class FeedProfileValidatorTest < ActiveSupport::TestCase
  def valid_entry
    {
      display_name: "Sample",
      description: "Sample profile for testing",
      input_shape: :url,
      depends_on_ai: false,
      scheduled: true,
      matcher: "ProfileMatcher::RssProfileMatcher",
      parameter_schema: {
        "type" => "object",
        "properties" => { "url" => { "type" => "string" } },
        "required" => ["url"]
      },
      loader: { class: "Loader::HttpLoader", config: {} },
      processor: { class: "Processor::RssProcessor", config: {} },
      normalizer: { class: "Normalizer::RssNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor"
    }
  end

  test ".validate! should validate the live FeedProfile::PROFILES registry" do
    assert_nothing_raised { FeedProfileValidator.validate! }
  end

  test ".validate! should accept a valid registry" do
    assert_nothing_raised do
      FeedProfileValidator.validate!("sample" => valid_entry)
    end
  end

  test ".validate! should accept an explicitly unscheduled profile" do
    assert_nothing_raised do
      FeedProfileValidator.validate!("sample" => valid_entry.merge(scheduled: false))
    end
  end

  test ".validate! should accept optional profile defaults" do
    assert_nothing_raised do
      FeedProfileValidator.validate!("sample" => valid_entry.merge(defaults: { images_only: false }))
    end
  end

  test ".validate! should reject entry missing required key" do
    entry = valid_entry.except(:display_name)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "display_name"
  end

  test ".validate! should require the scheduling capability to be explicit" do
    entry = valid_entry.except(:scheduled)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "scheduled"
  end

  test ".validate! should reject entry with unknown input_shape" do
    entry = valid_entry.merge(input_shape: :twitter)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "input_shape"
  end

  test ".validate! should reject stage entry that is a bare string instead of {class:, config:}" do
    entry = valid_entry.merge(loader: "Loader::HttpLoader")

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "loader"
  end

  test ".validate! should reject stage entry missing class" do
    entry = valid_entry.merge(loader: { config: {} })

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "loader"
    assert_includes error.message, "class"
  end

  test ".validate! should reject unknown extra keys at top level" do
    entry = valid_entry.merge(rogue_key: 42)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "rogue_key"
  end

  test ".validate! should require a loader output_schema when depends_on_ai is true" do
    entry = valid_entry.merge(depends_on_ai: true)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "loader.config.output_schema is required when depends_on_ai is true"
  end

  test ".validate! should accept AI profile with a loader output_schema" do
    entry = valid_entry.except(:matcher).merge(
      depends_on_ai: true,
      loader: { class: "Loader::LlmLoader", config: { output_schema: { "type" => "object" } } }
    )

    assert_nothing_raised do
      FeedProfileValidator.validate!("sample" => entry)
    end
  end

  test ".validate! should require a matcher for non-AI profiles" do
    entry = valid_entry.except(:matcher)

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "matcher is required for non-AI profiles"
  end

  test ".validate! should accept an AI profile without a matcher (structural detection exclusion)" do
    entry = valid_entry.except(:matcher)
                       .merge(depends_on_ai: true,
                              loader: { class: "Loader::LlmLoader", config: { output_schema: { "type" => "object" } } })

    assert_nothing_raised do
      FeedProfileValidator.validate!("sample" => entry)
    end
  end

  test ".validate! should reject an AI profile that registers a matcher" do
    entry = valid_entry.merge(depends_on_ai: true,
                              loader: { class: "Loader::LlmLoader", config: { output_schema: { "type" => "object" } } })

    error = assert_raises(FeedProfileValidator::Error) do
      FeedProfileValidator.validate!("sample" => entry)
    end

    assert_includes error.message, "matcher must be absent for AI profiles"
  end
end
