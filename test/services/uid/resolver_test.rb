require "test_helper"

class Uid::ResolverTest < ActiveSupport::TestCase
  test "#call should normalize a deep-link permalink into a uid" do
    item = { "source_url" => "https://Example.COM/Blog/Post-1/" }
    assert_equal "https://example.com/Blog/Post-1", Uid::Resolver.call(item)
  end

  test "#call should strip tracking params and fragments" do
    item = { "source_url" => "https://example.com/p/9?utm_source=rss&id=7&fbclid=abc#top" }
    assert_equal "https://example.com/p/9?id=7", Uid::Resolver.call(item)
  end

  test "#call should drop a query that is only tracking params" do
    item = { "source_url" => "https://example.com/p/9?utm_source=rss" }
    assert_equal "https://example.com/p/9", Uid::Resolver.call(item)
  end

  test "#call should accept symbol keys" do
    item = { source_url: "https://example.com/a" }
    assert_equal "https://example.com/a", Uid::Resolver.call(item)
  end

  test "#call should return nil for a bare homepage" do
    assert_nil Uid::Resolver.call({ "source_url" => "https://example.com/" })
  end

  test "#call should return nil when source_url is missing" do
    assert_nil Uid::Resolver.call({ "body" => "hi" })
  end

  test "#call should return nil for a non-http or malformed url" do
    assert_nil Uid::Resolver.call({ "source_url" => "ftp://example.com/x" })
    assert_nil Uid::Resolver.call({ "source_url" => "not a url" })
  end

  test "#call should be deterministic for the same permalink" do
    item = { "source_url" => "https://example.com/post/1" }
    assert_equal Uid::Resolver.call(item), Uid::Resolver.call(item)
  end
end
