require "test_helper"

class SourceLinkTest < ActiveSupport::TestCase
  test ".canonical should honor an explicit http(s) URL as typed" do
    assert_equal "https://example.com", SourceLink.canonical("https://example.com")
    assert_equal "https://example.com/feed.xml", SourceLink.canonical("https://example.com/feed.xml")
    assert_equal "https://example.com/path?q=1#hash", SourceLink.canonical("https://example.com/path?q=1#hash")
    assert_equal "https://example.com:8080/path", SourceLink.canonical("https://example.com:8080/path")
  end

  test ".canonical should never force http to https" do
    assert_equal "http://example.com", SourceLink.canonical("http://example.com")
    assert_equal "http://localhost:3000/", SourceLink.canonical("http://localhost:3000/")
  end

  test ".canonical should scheme-fix a bare, host-shaped input" do
    assert_equal "https://example.com", SourceLink.canonical("example.com")
    assert_equal "https://example.com/feed.xml", SourceLink.canonical("example.com/feed.xml")
    assert_equal "https://blog.example.com/path?q=1", SourceLink.canonical("blog.example.com/path?q=1")
  end

  test ".canonical should not scheme-fix something that isn't host-shaped" do
    # `r/x` must not become `https://r/x` (host `r`) — it routes to the AI bridge.
    assert_nil SourceLink.canonical("r/x")
    assert_nil SourceLink.canonical("user/someone")
    assert_nil SourceLink.canonical("localhost:3000")
  end

  test ".canonical should reject a host with a leading or trailing dot" do
    assert_nil SourceLink.canonical(".example.com")
    assert_nil SourceLink.canonical("example.com.")
  end

  test ".canonical should reject handles and free text" do
    assert_nil SourceLink.canonical("@user")
    assert_nil SourceLink.canonical("@user@mastodon.social")
    assert_nil SourceLink.canonical("ruby on rails news")
    assert_nil SourceLink.canonical("dog")
  end

  test ".canonical should reject non-http schemes" do
    assert_nil SourceLink.canonical("ftp://example.com")
    assert_nil SourceLink.canonical("file:///etc/passwd")
    assert_nil SourceLink.canonical("javascript:alert(1)")
    assert_nil SourceLink.canonical("mailto:me@example.com")
  end

  test ".canonical should reject a hostless http string" do
    assert_nil SourceLink.canonical("https://")
    assert_nil SourceLink.canonical("http:///path")
  end

  test ".canonical should honor a punycode-encoded IDN but reject a raw one" do
    assert_equal "https://xn--r8jz45g.example/", SourceLink.canonical("https://xn--r8jz45g.example/")
    # Ruby's URI.parse rejects non-ASCII hosts; a raw IDN isn't a URL here.
    assert_nil SourceLink.canonical("https://例え.テスト/")
  end

  test ".canonical should strip surrounding whitespace" do
    assert_equal "https://example.com", SourceLink.canonical("  https://example.com  ")
    assert_equal "https://example.com", SourceLink.canonical("  example.com\n")
  end

  test ".canonical should return nil for blank input" do
    assert_nil SourceLink.canonical("")
    assert_nil SourceLink.canonical(nil)
    assert_nil SourceLink.canonical("   ")
  end

  test ".url? should mirror whether canonical returns a URL" do
    assert SourceLink.url?("example.com")
    assert SourceLink.url?("http://example.com")
    assert_not SourceLink.url?("r/x")
    assert_not SourceLink.url?("hello world")
  end
end
