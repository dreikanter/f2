require "test_helper"

class Normalizer::BaseTest < ActiveSupport::TestCase
  def feed_entry
    @feed_entry ||= create(:feed_entry)
  end

  def normalizer
    @normalizer ||= Normalizer::Base.new(feed_entry)
  end

  test "should initialize without errors" do
    assert_nothing_raised do
      Normalizer::Base.new(feed_entry)
    end
  end

  test "extract_source_url should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      normalizer.send(:extract_source_url, {})
    end
    assert_equal "Subclasses must implement #extract_source_url", error.message
  end

  test "extract_content should raise NotImplementedError" do
    error = assert_raises(NotImplementedError) do
      normalizer.send(:extract_content, {})
    end
    assert_equal "Subclasses must implement #extract_content", error.message
  end

  test "extract_attachment_urls should return empty array by default" do
    result = normalizer.send(:extract_attachment_urls, {})
    assert_equal [], result
  end

  test "extract_comments should return empty array by default" do
    result = normalizer.send(:extract_comments, {})
    assert_equal [], result
  end
end
