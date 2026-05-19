require "test_helper"

class Processor::PassthroughProcessorTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     llm_credential: create(:llm_credential, :active, user: user),
                     feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" })
  end

  test "#process should build a FeedEntry for each item with a uid" do
    items = [
      { "uid" => "https://example.com/a", "title" => "A", "published_at" => "2026-05-01T00:00:00Z" },
      { "uid" => "https://example.com/b", "title" => "B" }
    ]

    entries = Processor::PassthroughProcessor.new(feed, items).process

    assert_equal 2, entries.size
    assert_equal "https://example.com/a", entries[0].uid
    assert_equal "https://example.com/b", entries[1].uid
    assert_kind_of FeedEntry, entries[0]
  end

  test "#process should skip items missing a uid" do
    items = [
      { "title" => "no uid" },
      { "uid" => "https://example.com/ok" }
    ]

    entries = Processor::PassthroughProcessor.new(feed, items).process

    assert_equal 1, entries.size
    assert_equal "https://example.com/ok", entries[0].uid
  end

  test "#process should parse published_at from ISO 8601" do
    items = [{ "uid" => "u1", "published_at" => "2026-04-15T12:30:00Z" }]

    entries = Processor::PassthroughProcessor.new(feed, items).process

    assert_kind_of Time, entries[0].published_at
    assert_equal 2026, entries[0].published_at.year
  end

  test "#process should tolerate invalid published_at strings" do
    items = [{ "uid" => "u1", "published_at" => "not a date" }]

    entries = Processor::PassthroughProcessor.new(feed, items).process

    assert_nil entries[0].published_at
  end

  test "#process should accept symbol keys as well as strings" do
    items = [{ uid: "u-sym", title: "Sym" }]

    entries = Processor::PassthroughProcessor.new(feed, items).process

    assert_equal "u-sym", entries[0].uid
    assert_equal "u-sym", entries[0].raw_data["uid"]
  end
end
