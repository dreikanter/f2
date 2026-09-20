require "test_helper"

class Uid::ResolverTest < ActiveSupport::TestCase
  test ".from_url should normalize a deep-link permalink into a uid" do
    assert_equal "https://example.com/Blog/Post-1", Uid::Resolver.from_url("https://Example.COM/Blog/Post-1/")
  end

  test ".from_url should strip tracking params and fragments" do
    assert_equal "https://example.com/p/9?id=7", Uid::Resolver.from_url("https://example.com/p/9?utm_source=rss&id=7&fbclid=abc#top")
  end

  test ".from_url should drop a query that is only tracking params" do
    assert_equal "https://example.com/p/9", Uid::Resolver.from_url("https://example.com/p/9?utm_source=rss")
  end

  test ".from_url should coerce the scheme to https so http/https don't split a uid" do
    assert_equal "https://example.com/a", Uid::Resolver.from_url("http://example.com/a")
  end

  test ".from_url should strip a leading www so it doesn't split a uid" do
    assert_equal "https://example.com/a", Uid::Resolver.from_url("https://www.example.com/a")
  end

  test ".from_url should strip the default HTTPS port" do
    assert_equal "https://example.com/a", Uid::Resolver.from_url("https://example.com:443/a")
  end

  test ".from_url should strip the default HTTP port" do
    assert_equal "https://example.com/a", Uid::Resolver.from_url("http://example.com:80/a")
  end

  test ".from_url should percent-encode a non-ASCII path instead of dropping the item" do
    assert_equal "https://example.com/%D1%81%D1%82%D0%B0%D1%82%D1%8C%D1%8F",
                 Uid::Resolver.from_url("https://example.com/статья")
  end

  test ".from_url should be idempotent under the hardening rules" do
    once = Uid::Resolver.from_url("http://www.Example.com:80/Post/?utm_source=x#frag")

    assert_equal once, Uid::Resolver.from_url(once)
  end

  test ".from_url should return nil for a missing URL" do
    assert_nil Uid::Resolver.from_url(nil)
  end

  test ".from_url should return nil for a blank URL" do
    assert_nil Uid::Resolver.from_url("   ")
  end

  test ".from_url should return nil for a bare homepage" do
    assert_nil Uid::Resolver.from_url("https://example.com/")
  end

  test ".from_url should return nil for a non-HTTP URL" do
    assert_nil Uid::Resolver.from_url("ftp://example.com/x")
  end

  test ".from_url should return nil for a malformed URL" do
    assert_nil Uid::Resolver.from_url("not a url")
  end
end
