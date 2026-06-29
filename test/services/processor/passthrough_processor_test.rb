require "test_helper"

class Processor::PassthroughProcessorTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     ai_credential: create(:ai_credential, :active, user: user),
                     feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" })
  end

  def process(items) = Processor::PassthroughProcessor.new(feed, items).process

  test "#process should derive a normalized permalink uid and ignore model-supplied uid" do
    items = [{ "uid" => "ephemeral-123", "source_url" => "https://Example.com/post/1/?utm_source=x", "title" => "A" }]

    entries = process(items).entries

    assert_equal 1, entries.size
    assert_equal "https://example.com/post/1", entries.first.uid
    assert_kind_of FeedEntry, entries.first
  end

  test "#process should build an entry per item with a usable permalink" do
    items = [
      { "source_url" => "https://example.com/a", "title" => "A", "published_at" => "2026-05-01T00:00:00Z" },
      { "source_url" => "https://example.com/b", "title" => "B" }
    ]

    entries = process(items).entries

    assert_equal ["https://example.com/a", "https://example.com/b"], entries.map(&:uid)
  end

  test "#process should produce identical uids across separate runs" do
    items = [{ "source_url" => "https://example.com/a", "title" => "x" }]

    first = process(items).entries.first.uid
    second = process(items).entries.first.uid

    assert_equal first, second
  end

  test "#process should drop items without a usable permalink" do
    items = [
      { "title" => "no url" },
      { "source_url" => "https://example.com/", "title" => "homepage only" },
      { "source_url" => "https://example.com/ok", "title" => "good" }
    ]

    entries = process(items).entries

    assert_equal ["https://example.com/ok"], entries.map(&:uid)
  end

  test "#process should parse published_at from ISO 8601" do
    items = [{ "source_url" => "https://example.com/a", "published_at" => "2026-04-15T12:30:00Z" }]

    entries = process(items).entries

    assert_kind_of Time, entries[0].published_at
    assert_equal 2026, entries[0].published_at.year
  end

  test "#process should default to the current time when published_at is invalid" do
    items = [{ "source_url" => "https://example.com/a", "published_at" => "not a date" }]

    entries = process(items).entries

    assert_in_delta Time.current.to_f, entries[0].published_at.to_f, 5.0
  end

  test "#process should accept symbol keys" do
    items = [{ source_url: "https://example.com/sym", title: "Sym" }]

    entries = process(items).entries

    assert_equal "https://example.com/sym", entries[0].uid
  end
end
