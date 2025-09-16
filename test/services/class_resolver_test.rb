require "test_helper"
require "minitest/mock"

class ClassResolverTest < ActiveSupport::TestCase
  test "resolves existing class with correct scope and key" do
    # Test with known existing classes
    processor_class = ClassResolver.resolve("Processor", "rss_processor")
    assert_equal Processor::RssProcessor, processor_class

    normalizer_class = ClassResolver.resolve("Normalizer", "rss_normalizer")
    assert_equal Normalizer::RssNormalizer, normalizer_class

    loader_class = ClassResolver.resolve("Loader", "http_loader")
    assert_equal Loader::HttpLoader, loader_class
  end

  test "handles key camelization correctly" do
    # Test that snake_case keys are properly camelized
    loader_class = ClassResolver.resolve("Loader", "http_loader")

    # Should successfully find Loader::HttpLoader
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

  test "class method resolve works correctly" do
    # Test the class method interface directly
    result = ClassResolver.resolve("Processor", "rss_processor")
    assert_equal Processor::RssProcessor, result

    # Verify it's equivalent to instance method
    resolver_instance = ClassResolver.new("Processor", "rss_processor")
    instance_result = resolver_instance.resolve
    assert_equal result, instance_result
  end

  test "builds correct class name from scope and key" do
    resolver = ClassResolver.new("TestScope", "test_key")

    # Access private method for testing
    class_name = resolver.send(:build_class_name)
    assert_equal "TestScope::TestKey", class_name
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
    # Should work with different cases in scope
    error1 = assert_raises(ArgumentError) do
      ClassResolver.resolve("loader", "unknown")
    end
    assert_equal "Unknown loader: unknown", error1.message

    error2 = assert_raises(ArgumentError) do
      ClassResolver.resolve("LOADER", "unknown")
    end
    assert_equal "Unknown loader: unknown", error2.message
  end

  test "resolver instance maintains state correctly" do
    resolver = ClassResolver.new("Processor", "rss_processor")

    # Should be able to call resolve multiple times
    result1 = resolver.resolve
    result2 = resolver.resolve

    assert_equal result1, result2
    assert_equal Processor::RssProcessor, result1
  end
end