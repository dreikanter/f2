require "test_helper"

class Uid::ResolverTest < ActiveSupport::TestCase
  def uid_for(item)
    Uid::Resolver.from_url(item.stringify_keys["source_url"])
  end

  test ".from_url should normalize a deep-link permalink into a uid" do
    assert_equal "https://example.com/Blog/Post-1", uid_for({ "source_url" => "https://Example.COM/Blog/Post-1/" })
  end

  test ".from_url should strip tracking params and fragments" do
    assert_equal "https://example.com/p/9?id=7", uid_for({ "source_url" => "https://example.com/p/9?utm_source=rss&id=7&fbclid=abc#top" })
  end

  test ".from_url should drop a query that is only tracking params" do
    assert_equal "https://example.com/p/9", uid_for({ "source_url" => "https://example.com/p/9?utm_source=rss" })
  end

  test ".from_url should accept symbol keys" do
    assert_equal "https://example.com/a", uid_for({ source_url: "https://example.com/a" })
  end

  test ".from_url should return nil for a bare homepage" do
    assert_nil uid_for({ "source_url" => "https://example.com/" })
  end

  test ".from_url should return nil when source_url is missing" do
    assert_nil uid_for({ "body" => "hi" })
  end

  test ".from_url should return nil for a non-http or malformed url" do
    assert_nil uid_for({ "source_url" => "ftp://example.com/x" })
    assert_nil uid_for({ "source_url" => "not a url" })
  end

  test ".from_url should be deterministic for the same permalink" do
    item = { "source_url" => "https://example.com/post/1" }
    assert_equal uid_for(item), uid_for(item)
  end

  test ".from_url should coerce the scheme to https so http/https don't split a uid" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "http://example.com/a" })
    assert_equal uid_for({ "source_url" => "http://example.com/a" }), uid_for({ "source_url" => "https://example.com/a" })
  end

  test ".from_url should strip a leading www. so it doesn't split a uid" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "https://www.example.com/a" })
  end

  test ".from_url should strip default ports" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "https://example.com:443/a" })
    assert_equal "https://example.com/a", uid_for({ "source_url" => "http://example.com:80/a" })
  end

  test ".from_url should percent-encode a non-ASCII path instead of dropping the item" do
    assert_equal "https://example.com/%D1%81%D1%82%D0%B0%D1%82%D1%8C%D1%8F",
                 uid_for({ "source_url" => "https://example.com/статья" })
  end

  test ".from_url should be idempotent under the hardening rules" do
    once = uid_for({ "source_url" => "http://www.Example.com:80/Post/?utm_source=x#frag" })
    assert_equal once, uid_for({ "source_url" => once })
  end

  test ".from_url should mint the same uid as an item carrying that permalink" do
    url = "https://Example.COM/Blog/Post-1/?utm_source=rss#top"

    assert_equal "https://example.com/Blog/Post-1", Uid::Resolver.from_url(url)
    assert_equal uid_for({ "source_url" => url }), Uid::Resolver.from_url(url)
  end

  test ".from_url should return nil for a url that can't anchor an identity" do
    assert_nil Uid::Resolver.from_url(nil)
    assert_nil Uid::Resolver.from_url("   ")
    assert_nil Uid::Resolver.from_url("https://example.com/")
    assert_nil Uid::Resolver.from_url("not a url")
  end
end
