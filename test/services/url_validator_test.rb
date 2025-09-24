require "test_helper"

class UrlValidatorTest < ActiveSupport::TestCase
  test "should return true for valid http and https urls" do
    valid_urls = [
      "http://example.com",
      "https://example.com",
      "http://example.com/path",
      "https://example.com/path",
      "http://example.com/path?query=value",
      "https://example.com/path?query=value",
      "http://example.com:8080",
      "https://example.com:8080",
      "http://subdomain.example.com",
      "https://subdomain.example.com"
    ]

    valid_urls.each do |url|
      assert UrlValidator.valid?(url), "Expected #{url} to be valid"
    end
  end

  test "should return false for invalid schemes" do
    invalid_urls = [
      "ftp://example.com",
      "file:///path/to/file",
      "mailto:test@example.com",
      "javascript:alert('xss')",
      "data:text/plain;base64,SGVsbG8gV29ybGQ="
    ]

    invalid_urls.each do |url|
      assert_not UrlValidator.valid?(url), "Expected #{url} to be invalid"
    end
  end

  test "should return false for malformed urls" do
    invalid_urls = [
      "not-a-url",
      "://example.com",
      "http//example.com"
    ]

    invalid_urls.each do |url|
      assert_not UrlValidator.valid?(url), "Expected #{url} to be invalid"
    end
  end

  test "should return false for nil, empty, or blank urls" do
    invalid_urls = [nil, "", "   "]

    invalid_urls.each do |url|
      assert_not UrlValidator.valid?(url), "Expected #{url.inspect} to be invalid"
    end
  end

  test "should handle urls with spaces by stripping them" do
    assert UrlValidator.valid?("  http://example.com  ")
    assert UrlValidator.valid?(" https://example.com ")
  end

  test "should handle URI::InvalidURIError gracefully" do
    # These URLs cause URI::InvalidURIError
    invalid_urls = [
      "http://[invalid",
      "http://example.com:abc"
    ]

    invalid_urls.each do |url|
      assert_not UrlValidator.valid?(url), "Expected #{url} to be handled gracefully"
    end
  end

  test "should accept urls with international domain names" do
    # These may or may not be valid depending on URI implementation,
    # but should not raise errors
    international_urls = [
      "http://例え.テスト",
      "https://测试.测试"
    ]

    international_urls.each do |url|
      assert_nothing_raised do
        UrlValidator.valid?(url)
      end
    end
  end

  test "should handle urls with fragments and complex queries" do
    complex_urls = [
      "http://example.com/path?param1=value1&param2=value2",
      "https://example.com/path#fragment",
      "http://example.com/path?query=value#fragment",
      "https://example.com:8080/complex/path?a=1&b=2#section"
    ]

    complex_urls.each do |url|
      assert UrlValidator.valid?(url), "Expected #{url} to be valid"
    end
  end
end
