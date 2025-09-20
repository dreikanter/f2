require "test_helper"

class ClassResolverTest < ActiveSupport::TestCase
  test "resolves existing class with correct scope and key" do
    processor_class = ClassResolver.resolve("Processor", "rss_processor")
    assert_equal Processor::RssProcessor, processor_class

    normalizer_class = ClassResolver.resolve("Normalizer", "rss_normalizer")
    assert_equal Normalizer::RssNormalizer, normalizer_class

    loader_class = ClassResolver.resolve("Loader", "http_loader")
    assert_equal Loader::HttpLoader, loader_class
  end

  test "raises ArgumentError for unknown scope" do
    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("UnknownScope", "test")
    end
    assert_equal "Unknown unknownscope: test", error.message
  end

  test "raises ArgumentError for unknown key in valid scope" do
    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("Loader", "unknown")
    end
    assert_equal "Unknown loader: unknown", error.message
  end

  test "handles empty and nil keys gracefully" do
    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("Loader", "")
    end
    assert_equal "Key cannot be nil or empty", error.message

    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("Loader", nil)
    end
    assert_equal "Key cannot be nil or empty", error.message

    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("Loader", "   ")
    end
    assert_equal "Key cannot be nil or empty", error.message
  end

  test "handles case variations in scope" do
    error1 = assert_raises(ArgumentError) do
      ClassResolver.resolve("loader", "unknown")
    end
    assert_equal "Unknown loader: unknown", error1.message

    error2 = assert_raises(ArgumentError) do
      ClassResolver.resolve("LOADER", "unknown")
    end
    assert_equal "Unknown loader: unknown", error2.message
  end

end
