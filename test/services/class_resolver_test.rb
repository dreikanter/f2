require "test_helper"

class ClassResolverTest < ActiveSupport::TestCase
  test "resolves existing class with correct scope and key" do
    processor_class = ClassResolver.resolve("Processor", "rss")
    assert_equal Processor::RssProcessor, processor_class

    normalizer_class = ClassResolver.resolve("Normalizer", "rss")
    assert_equal Normalizer::RssNormalizer, normalizer_class

    loader_class = ClassResolver.resolve("Loader", "http")
    assert_equal Loader::HttpLoader, loader_class

    extractor_class = ClassResolver.resolve("TitleExtractor", "rss")
    assert_equal TitleExtractor::RssTitleExtractor, extractor_class
  end

  test "raises ArgumentError for unknown scope" do
    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("UnknownScope", "test")
    end
    assert_equal "Can not resolve class UnknownScope::TestUnknownScope", error.message
  end

  test "raises ArgumentError for unknown key in valid scope" do
    error = assert_raises(ArgumentError) do
      ClassResolver.resolve("Loader", "unknown")
    end
    assert_equal "Can not resolve class Loader::UnknownLoader", error.message
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
    assert_equal "Can not resolve class loader::UnknownLoader", error1.message

    error2 = assert_raises(ArgumentError) do
      ClassResolver.resolve("LOADER", "unknown")
    end
    assert_equal "Can not resolve class LOADER::UnknownLoader", error2.message
  end

  test "always adds scope suffix to key" do
    processor_class = ClassResolver.resolve("Processor", "rss")
    assert_equal Processor::RssProcessor, processor_class

    extractor_class = ClassResolver.resolve("TitleExtractor", "rss")
    assert_equal TitleExtractor::RssTitleExtractor, extractor_class
  end
end
