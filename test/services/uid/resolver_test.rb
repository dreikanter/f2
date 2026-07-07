require "test_helper"

class Uid::ResolverTest < ActiveSupport::TestCase
  # Fixed clock so digest period uids are deterministic.
  def clock
    @clock ||= Time.utc(2026, 7, 7, 9, 30, 0)
  end

  def uid_for(item)
    Uid::Resolver.call(item, clock: clock)
  end

  test "#call should normalize a deep-link permalink into a uid" do
    assert_equal "https://example.com/Blog/Post-1", uid_for({ "source_url" => "https://Example.COM/Blog/Post-1/" })
  end

  test "#call should strip tracking params and fragments" do
    assert_equal "https://example.com/p/9?id=7", uid_for({ "source_url" => "https://example.com/p/9?utm_source=rss&id=7&fbclid=abc#top" })
  end

  test "#call should drop a query that is only tracking params" do
    assert_equal "https://example.com/p/9", uid_for({ "source_url" => "https://example.com/p/9?utm_source=rss" })
  end

  test "#call should accept symbol keys" do
    assert_equal "https://example.com/a", uid_for({ source_url: "https://example.com/a" })
  end

  test "#call should return nil for a bare homepage" do
    assert_nil uid_for({ "source_url" => "https://example.com/" })
  end

  test "#call should return nil when source_url is missing" do
    assert_nil uid_for({ "body" => "hi" })
  end

  test "#call should return nil for a non-http or malformed url" do
    assert_nil uid_for({ "source_url" => "ftp://example.com/x" })
    assert_nil uid_for({ "source_url" => "not a url" })
  end

  test "#call should be deterministic for the same permalink" do
    item = { "source_url" => "https://example.com/post/1" }
    assert_equal uid_for(item), uid_for(item)
  end

  test "#call should coerce the scheme to https so http/https don't split a uid" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "http://example.com/a" })
    assert_equal uid_for({ "source_url" => "http://example.com/a" }), uid_for({ "source_url" => "https://example.com/a" })
  end

  test "#call should strip a leading www. so it doesn't split a uid" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "https://www.example.com/a" })
  end

  test "#call should strip default ports" do
    assert_equal "https://example.com/a", uid_for({ "source_url" => "https://example.com:443/a" })
    assert_equal "https://example.com/a", uid_for({ "source_url" => "http://example.com:80/a" })
  end

  test "#call should percent-encode a non-ASCII path instead of dropping the item" do
    assert_equal "https://example.com/%D1%81%D1%82%D0%B0%D1%82%D1%8C%D1%8F",
                 uid_for({ "source_url" => "https://example.com/статья" })
  end

  test "#call should be idempotent under the hardening rules" do
    once = uid_for({ "source_url" => "http://www.Example.com:80/Post/?utm_source=x#frag" })
    assert_equal once, uid_for({ "source_url" => once })
  end

  test "#call should mint a period uid for an explicit null source_url (digest regime)" do
    assert_equal "digest:2026-07-07", uid_for({ "source_url" => nil, "body" => "roundup" })
    assert_equal "digest:2026-07-07", uid_for({ source_url: nil })
  end

  test "#call should key the digest uid to the UTC date of the run" do
    later = Time.utc(2026, 7, 8, 1, 0, 0)
    assert_equal "digest:2026-07-08", Uid::Resolver.call({ "source_url" => nil }, clock: later)
  end

  test "#call should treat a missing key or empty string as unusable, not digest" do
    assert_nil uid_for({ "body" => "no source_url key" })
    assert_nil uid_for({ "source_url" => "" })
    assert_nil uid_for({ "source_url" => "   " })
  end

  test ".digest_period should be the clock's UTC date" do
    assert_equal Date.new(2026, 7, 7), Uid::Resolver.digest_period(clock)
  end

  test ".digest_uid? should recognize a period-keyed uid" do
    assert Uid::Resolver.digest_uid?(Uid::Resolver.digest_period_uid(clock))
    assert Uid::Resolver.digest_uid?("digest:2026-07-07")
  end

  test ".digest_uid? should be false for a permalink uid or blank" do
    assert_not Uid::Resolver.digest_uid?("https://example.com/a")
    assert_not Uid::Resolver.digest_uid?(nil)
    assert_not Uid::Resolver.digest_uid?("")
  end

  test ".digest_uid? should reject a loose or malformed digest-prefixed uid" do
    # A source-controlled guid that merely starts with "digest:" is not a digest.
    assert_not Uid::Resolver.digest_uid?("digest:foo")
    assert_not Uid::Resolver.digest_uid?("digest:2026-07-07/extra")
    assert_not Uid::Resolver.digest_uid?("prefix-digest:2026-07-07")
  end

  test ".period_from_uid should extract the date carried by a digest uid" do
    assert_equal Date.new(2026, 7, 7), Uid::Resolver.period_from_uid("digest:2026-07-07")
    assert_equal Uid::Resolver.digest_period(clock),
                 Uid::Resolver.period_from_uid(Uid::Resolver.digest_period_uid(clock))
  end

  test ".period_from_uid should return nil for a non-digest or invalid-date uid" do
    assert_nil Uid::Resolver.period_from_uid("https://example.com/a")
    assert_nil Uid::Resolver.period_from_uid("digest:2026-13-01")
    assert_nil Uid::Resolver.period_from_uid(nil)
  end
end
