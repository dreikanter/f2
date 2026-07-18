require "test_helper"

class WebhookIngestionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def feed
    @feed ||= create(:feed, :webhook, :enabled)
  end

  def endpoint
    @endpoint ||= create(:webhook_endpoint, feed: feed)
  end

  def ingest(payload)
    WebhookIngestion.new(endpoint: endpoint, payload: payload).call
  end

  test "#call should persist entry, uid record, and enqueued post" do
    result = nil

    assert_difference ["FeedEntry.count", "FeedEntryUid.count", "Post.count"], 1 do
      result = ingest({ "content" => "Hello world" })
    end

    assert result.enqueued?
    assert result.uid.present?
    assert_empty result.warnings

    entry = feed.feed_entries.sole
    assert_predicate entry, :processed?
    assert_equal({ "content" => "Hello world" }, entry.raw_data)

    post = feed.posts.sole
    assert_predicate post, :enqueued?
    assert_equal "Hello world", post.content
  end

  test "#call should kick the publish chain on success" do
    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      ingest({ "content" => "Hello world" })
    end
  end

  test "#call should update endpoint counters on success" do
    freeze_time do
      ingest({ "content" => "Hello world" })

      assert_equal 1, endpoint.reload.received_count
      assert_equal Time.current, endpoint.last_received_at
    end
  end

  test "#call should prefer the explicit uid" do
    result = ingest({ "content" => "Hello", "uid" => "article-42", "source_url" => "https://example.com/a" })

    assert_equal "article-42", result.uid
  end

  test "#call should derive the uid from source_url like pull feeds" do
    result = ingest({ "content" => "Hello", "source_url" => "http://www.example.com/a?utm_source=x" })

    assert_equal "https://example.com/a", result.uid
  end

  test "#call should fall back to a random uid" do
    first = ingest({ "content" => "Hello" })
    second = ingest({ "content" => "Hello" })

    assert first.enqueued?
    assert second.enqueued?
    assert_not_equal first.uid, second.uid
  end

  test "#call should report a duplicate uid without persisting anything" do
    ingest({ "content" => "Hello", "uid" => "article-42" })

    result = nil
    assert_no_difference ["FeedEntry.count", "Post.count"] do
      result = ingest({ "content" => "Changed content", "uid" => "article-42" })
    end

    assert result.duplicate?
    assert_equal "article-42", result.uid
  end

  test "#call should touch last_received_at but not received_count on duplicate" do
    ingest({ "content" => "Hello", "uid" => "article-42" })

    travel 5.minutes do
      ingest({ "content" => "Hello", "uid" => "article-42" })

      assert_equal 1, endpoint.reload.received_count
      assert_equal Time.current, endpoint.last_received_at
    end
  end

  test "#call should map an insert race to a duplicate" do
    ingestion = WebhookIngestion.new(endpoint: endpoint, payload: { "content" => "Hello", "uid" => "article-42" })
    race = ->(*) { raise ActiveRecord::RecordNotUnique, "duplicate key" }

    result = FeedEntryUid.stub(:create!, race) { ingestion.call }

    assert result.duplicate?
    assert_equal 0, feed.feed_entries.count
  end

  test "#call should reject a payload with unknown fields" do
    result = nil

    assert_no_difference ["FeedEntry.count", "FeedEntryUid.count", "Post.count"] do
      result = ingest({ "content" => "Hello", "imges" => ["https://example.com/pic.jpg"] })
    end

    assert result.invalid?
    assert result.errors.any?
  end

  test "#call should reject a payload without content or images" do
    result = ingest({ "comments" => ["First"] })

    assert result.invalid?
    assert_includes result.errors, "no_content_or_images"
  end

  test "#call should reject more than eight images" do
    urls = Array.new(9) { |n| "https://example.com/#{n}.jpg" }

    result = ingest({ "images" => urls })

    assert result.invalid?
  end

  test "#call should reject a relative source_url" do
    result = ingest({ "content" => "Hello", "source_url" => "/relative/path" })

    assert result.invalid?
    assert_includes result.errors, "source_url must be an absolute http(s) URL"
  end

  test "#call should reject a non-public image URL" do
    result = ingest({ "content" => "Hello", "images" => ["http://localhost/pic.jpg"] })

    assert result.invalid?
    assert_includes result.errors, "images/0 must be a public http(s) URL"
  end

  test "#call should reject an overlong source_url" do
    result = nil

    assert_no_difference ["FeedEntry.count", "Post.count"] do
      result = ingest({ "content" => "Hello", "source_url" => "https://example.com/#{"a" * 3000}" })
    end

    assert result.invalid?
  end

  test "#call should fall back to a random uid when the normalized url overflows the index" do
    url = "https://example.com/#{"я" * 1000}"

    result = ingest({ "content" => "Hello", "source_url" => url })

    assert result.enqueued?
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, result.uid)
  end

  test "#call should reject a malformed published_at" do
    result = ingest({ "content" => "Hello", "published_at" => "yesterday" })

    assert result.invalid?
    assert_includes result.errors, "published_at must be an ISO 8601 timestamp"
  end

  test "#call should persist nothing when the normalizer rejects the payload" do
    feed.update!(images_only: true)

    result = nil
    assert_no_difference ["FeedEntry.count", "FeedEntryUid.count", "Post.count"] do
      result = ingest({ "content" => "Text without images" })
    end

    assert result.invalid?
    assert_includes result.errors, "no_images"
    assert_equal 0, endpoint.reload.received_count
  end

  test "#call should store published_at on the entry" do
    ingest({ "content" => "Hello", "published_at" => "2026-07-11T12:00:00Z" })

    assert_equal Time.iso8601("2026-07-11T12:00:00Z"), feed.feed_entries.sole.published_at
  end

  test "#call should clamp a future published_at to now" do
    freeze_time do
      ingest({ "content" => "Hello", "published_at" => 2.days.from_now.iso8601 })

      assert_equal Time.current, feed.posts.sole.published_at
    end
  end

  test "#call should warn when content gets truncated" do
    result = ingest({ "content" => "a" * (Post::MAX_CONTENT_LENGTH + 1) })

    assert result.enqueued?
    assert_includes result.warnings, "content_truncated"
  end

  test "#call should warn when the source link squeezes the content" do
    url = "https://example.com/article"
    content = "a" * (Post::MAX_CONTENT_LENGTH - url.length)

    result = ingest({ "content" => content, "source_url" => url })

    assert result.enqueued?
    assert_includes result.warnings, "content_truncated"
  end

  test "#call should not warn when content fits" do
    result = ingest({ "content" => "Short and sweet" })

    assert_empty result.warnings
  end

  test "#call should keep public image URLs as attachments" do
    result = ingest({ "content" => "Hello", "images" => ["https://example.com/pic.jpg"] })

    assert result.enqueued?
    assert_equal ["https://example.com/pic.jpg"], feed.posts.sole.attachment_urls
  end
end
