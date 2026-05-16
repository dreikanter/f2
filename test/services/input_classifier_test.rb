require "test_helper"

class InputClassifierTest < ActiveSupport::TestCase
  test ".classify should return :url for http URLs" do
    assert_equal :url, InputClassifier.classify("http://example.com")
    assert_equal :url, InputClassifier.classify("https://example.com")
    assert_equal :url, InputClassifier.classify("https://example.com/feed.xml")
    assert_equal :url, InputClassifier.classify("https://example.com/path?q=1#hash")
  end

  test ".classify should return :url for URLs with paths and ports" do
    assert_equal :url, InputClassifier.classify("https://example.com:8080/path")
    assert_equal :url, InputClassifier.classify("http://localhost:3000/")
  end

  test ".classify should not classify ftp/file/javascript schemes as :url" do
    assert_not_equal :url, InputClassifier.classify("ftp://example.com")
    assert_not_equal :url, InputClassifier.classify("file:///etc/passwd")
    assert_not_equal :url, InputClassifier.classify("javascript:alert(1)")
  end

  test ".classify should return :url for punycode-encoded IDN URLs" do
    assert_equal :url, InputClassifier.classify("https://xn--r8jz45g.example/")
  end

  test ".classify should fall back to :query for raw IDN URLs that URI.parse cannot handle" do
    # Ruby's stdlib URI.parse rejects non-ASCII hostnames; the user would
    # need a punycode-encoded URL. The form-layer is responsible for
    # nudging them — the classifier is intentionally strict.
    assert_equal :query, InputClassifier.classify("https://例え.テスト/")
  end

  test ".classify should not classify a hostless http string as :url" do
    assert_not_equal :url, InputClassifier.classify("https://")
    assert_not_equal :url, InputClassifier.classify("http:///path")
  end

  test ".classify should return :handle for fediverse-shaped handles" do
    assert_equal :handle, InputClassifier.classify("@user")
    assert_equal :handle, InputClassifier.classify("@alice_42")
    assert_equal :handle, InputClassifier.classify("@user@mastodon.social")
    assert_equal :handle, InputClassifier.classify("@user@sub.example.com")
  end

  test ".classify should not return :handle for malformed handle strings" do
    assert_not_equal :handle, InputClassifier.classify("@")
    assert_not_equal :handle, InputClassifier.classify("@user@")
    assert_not_equal :handle, InputClassifier.classify("@user@@instance")
    assert_not_equal :handle, InputClassifier.classify("user@example.com")
    assert_not_equal :handle, InputClassifier.classify("@with spaces")
  end

  test ".classify should return :query for non-URL, non-handle text within length bounds" do
    assert_equal :query, InputClassifier.classify("ruby on rails news")
    assert_equal :query, InputClassifier.classify("xkcd comics")
    assert_equal :query, InputClassifier.classify("dog")
  end

  test ".classify should return :malformed for query-shaped strings shorter than QUERY_MIN_LENGTH" do
    assert_equal :malformed, InputClassifier.classify("ok")
  end

  test ".classify should return :malformed for blank or single-char inputs" do
    assert_equal :malformed, InputClassifier.classify("")
    assert_equal :malformed, InputClassifier.classify(nil)
    assert_equal :malformed, InputClassifier.classify("   ")
    assert_equal :malformed, InputClassifier.classify("a")
    assert_equal :malformed, InputClassifier.classify("\t\n")
  end

  test ".classify should strip whitespace before classifying" do
    assert_equal :url, InputClassifier.classify("  https://example.com  ")
    assert_equal :handle, InputClassifier.classify("  @user@instance.tld\n")
    assert_equal :query, InputClassifier.classify("  hello world  ")
  end

  test ".classify should return :malformed for excessively long queries" do
    long_input = "a" * (InputClassifier::QUERY_MAX_LENGTH + 1)
    assert_equal :malformed, InputClassifier.classify(long_input)
  end

  test ".classify should accept query at exactly QUERY_MAX_LENGTH" do
    boundary = "a" * InputClassifier::QUERY_MAX_LENGTH
    assert_equal :query, InputClassifier.classify(boundary)
  end
end
