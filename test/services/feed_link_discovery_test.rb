require "test_helper"

class FeedLinkDiscoveryTest < ActiveSupport::TestCase
  BASE_URL = "https://example.com/blog/post".freeze

  def discover(html, base_url: BASE_URL)
    FeedLinkDiscovery.call(html, base_url: base_url)
  end

  test "#call should collect typed alternate links in document order" do
    html = <<~HTML
      <html><head>
        <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
        <link rel="alternate" type="application/atom+xml" href="https://example.com/atom.xml">
        <link rel="alternate" type="application/feed+json" href="https://example.com/feed.json">
      </head><body></body></html>
    HTML

    assert_equal %w[
      https://example.com/feed.xml
      https://example.com/atom.xml
      https://example.com/feed.json
    ], discover(html)
  end

  test "#call should resolve relative hrefs against the base URL" do
    html = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      <link rel="alternate" type="application/atom+xml" href="atom.xml">
      <link rel="alternate" type="application/feed+json" href="//cdn.example.com/feed.json">
    HTML

    assert_equal %w[
      https://example.com/feed.xml
      https://example.com/blog/atom.xml
      https://cdn.example.com/feed.json
    ], discover(html)
  end

  test "#call should ignore links that are not typed feed alternates" do
    html = <<~HTML
      <link rel="stylesheet" href="/style.css">
      <link rel="preconnect" href="https://fonts.example.com">
      <link rel="alternate" type="text/html" hreflang="de" href="/de/">
      <link rel="alternate" href="/untyped">
      <link rel="icon" type="application/rss+xml" href="/not-alternate.xml">
    HTML

    assert_empty discover(html)
  end

  test "#call should match rel tokens and type parameters case-insensitively" do
    html = <<~HTML
      <link rel="ALTERNATE" type="Application/RSS+XML; charset=utf-8" href="/feed.xml">
    HTML

    assert_equal %w[https://example.com/feed.xml], discover(html)
  end

  test "#call should skip blank and unparseable hrefs" do
    html = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="">
      <link rel="alternate" type="application/rss+xml">
      <link rel="alternate" type="application/rss+xml" href="fe ed.xml">
      <link rel="alternate" type="application/rss+xml" href="/good.xml">
    HTML

    assert_equal %w[https://example.com/good.xml], discover(html)
  end

  test "#call should deduplicate repeated feed URLs" do
    html = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
    HTML

    assert_equal %w[https://example.com/feed.xml], discover(html)
  end

  test "#call should cap the result at three URLs" do
    links = (1..5).map do |n|
      %(<link rel="alternate" type="application/rss+xml" href="/feed-#{n}.xml">)
    end

    assert_equal %w[
      https://example.com/feed-1.xml
      https://example.com/feed-2.xml
      https://example.com/feed-3.xml
    ], discover(links.join("\n"))
  end

  test "#call should reject non-public feed URLs" do
    html = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="http://localhost/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="http://127.0.0.1/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="http://169.254.169.254/latest">
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
    HTML

    assert_equal %w[https://example.com/feed.xml], discover(html)
  end

  test "#call should return nothing for blank input or missing base" do
    html = %(<link rel="alternate" type="application/rss+xml" href="/feed.xml">)

    assert_empty discover(nil)
    assert_empty discover("")
    assert_empty discover(html, base_url: nil)
  end

  test "#call should return nothing for non-HTML text" do
    assert_empty discover("just some plain text without any markup")
  end
end
