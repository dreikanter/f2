require "test_helper"

class FeedIdentificationActivityTest < ActiveSupport::TestCase
  test "#finish! should record a readable feed and preserve its user and result after cleanup" do
    identification = create(:feed_identification, :no_feed, input: "https://example.com/feed.xml")
    stub_request(:get, identification.input).to_return(body: rss_body, headers: { "Content-Type" => "application/rss+xml" })

    freeze_time do
      identification.restart_detection
      started = events_for(identification).sole
      assert_equal "processing", started.metadata["status"]
      assert_equal identification.run_id, started.metadata["run_id"]
      assert_predicate started, :debug?

      travel 2.seconds
      FeedIdentificationJob.perform_now(identification.id, identification.run_id)

      event = events_for(identification).sole
      assert_not_equal started.id, event.id
      assert_equal identification.user, event.user
      assert_predicate event, :debug?
      assert_equal "working", event.metadata["status"]
      assert_equal identification.input, event.metadata["input"]
      assert_equal 2, event.metadata.dig("stats", "total_duration")
      assert_equal "rss", event.metadata["candidates"].sole["profile_key"]
      assert_equal "passed", event.metadata["candidates"].sole["test_status"]
      assert_equal 1, event.metadata["candidates"].sole["posts_found"]
      response = event.metadata.dig("diagnostics", "fetches").sole
      assert_equal 200, response["http_status"]
      assert_equal "application/rss+xml", response["content_type"]
      assert_equal rss_body.bytesize, response["body_bytes"]
      assert_not_includes event.metadata.to_json, "Private article text"
      assert_not Event.user_relevant.exists?(event.id)

      FeedIdentification.cleanup_for_source(user: identification.user, url: identification.input)

      assert_nil event.reload.subject
      assert_equal "working", event.metadata["status"]
      assert_equal identification.user, event.user
    end
  end

  test "#finish! should record HTTP rejection separately from an unrecognized page" do
    identification = create(:feed_identification, :no_feed, input: "https://example.com/feed.xml?token=secret#private")
    stub_request(:get, identification.input).to_return(status: 403, body: "Challenge body", headers: { "Content-Type" => "text/html" })

    identification.restart_detection
    FeedIdentificationJob.perform_now(identification.id, identification.run_id)

    event = events_for(identification).sole
    assert_equal "no_feed", event.metadata["status"]
    assert_equal "https://example.com/feed.xml", event.metadata["input"]
    assert_equal 403, event.metadata.dig("diagnostics", "fetches").sole["http_status"]
    assert_equal "HTTP 403", event.metadata.dig("diagnostics", "error", "message")
    assert_empty event.metadata["candidates"]
    assert_not_includes event.metadata.to_json, "secret"
    assert_not_includes event.metadata.to_json, "private"
    assert_not_includes event.metadata.to_json, "Challenge body"
  end

  test "#finish! should retain every discovered fetch and the chosen feed URL" do
    identification = create(:feed_identification, :no_feed, input: "https://example.com/blog")
    page = <<~HTML
      <html><head>
        <link rel="alternate" type="application/rss+xml" href="/blocked.xml">
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      </head><body>Blog</body></html>
    HTML
    stub_request(:get, identification.input).to_return(body: page)
    stub_request(:get, "https://example.com/blocked.xml").to_return(status: 429)
    stub_request(:get, "https://example.com/feed.xml").to_return(body: rss_body)

    identification.restart_detection
    FeedIdentificationJob.perform_now(identification.id, identification.run_id)

    event = events_for(identification).sole
    assert_equal [200, 429, 200], event.metadata.dig("diagnostics", "fetches").map { |response| response["http_status"] }
    assert_equal "working", event.metadata["status"]
    assert_equal "https://example.com/feed.xml", event.metadata["candidates"].sole["resolved_url"]
  end

  test "#finish! should retain candidate parser failures" do
    identification = create(:feed_identification, :no_feed, input: "https://xkcd.com/rss.xml")
    stub_request(:get, identification.input).to_return(body: "<html><body>Temporarily unavailable</body></html>")

    identification.restart_detection
    FeedIdentificationJob.perform_now(identification.id, identification.run_id)

    event = events_for(identification).sole
    candidate = event.metadata.dig("diagnostics", "candidate_tests").sole
    assert_equal "no_feed", event.metadata["status"]
    assert_equal "xkcd", candidate["profile_key"]
    assert_equal "failed", candidate["status"]
    assert_equal "Feedjira::NoParserAvailable", candidate["errors"].sole["class"]
  end

  test "#finish! should keep retries as separate attempts and record transport failures" do
    identification = create(:feed_identification, :no_feed)
    stub_request(:get, identification.input).to_timeout.then.to_return(body: rss_body)

    identification.restart_detection
    first_run = identification.run_id
    FeedIdentificationJob.perform_now(identification.id, first_run)
    first_event = events_for(identification).sole
    assert_equal "unreachable", first_event.metadata["status"]
    assert_equal "FeedIdentificationFetcher::UnreachableError", first_event.metadata.dig("diagnostics", "error", "class")

    identification.reload.restart_detection
    FeedIdentificationJob.perform_now(identification.id, identification.run_id)

    assert_equal 2, events_for(identification).count
    assert_equal "unreachable", first_event.reload.metadata["status"]
    latest = events_for(identification).where.not(id: first_event.id).sole
    assert_equal "working", latest.metadata["status"]
    assert_not_equal first_run, latest.metadata["run_id"]
  end

  test "#finish! should record timeouts once and ignore a late worker result" do
    identification = create(:feed_identification, :no_feed)
    identification.restart_detection
    run_id = identification.run_id
    late_fetcher = FeedIdentificationFetcher.new(feed_identification: identification, run_id: run_id)
    stub_request(:get, identification.input).to_return(body: rss_body)

    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)
    event = events_for(identification).sole
    assert_equal "timed_out", event.metadata["status"]
    assert_equal run_id, event.metadata["run_id"]

    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)
    late_fetcher.call

    assert_equal [event.id], events_for(identification).pluck(:id)
    assert_equal "timed_out", event.reload.metadata["status"]
  end

  test "#finish! should preserve cancelled attempts" do
    identification = create(:feed_identification, :no_feed)
    identification.restart_detection

    identification.destroy!

    event = events_for(identification).sole
    assert_equal "cancelled", event.metadata["status"]
    assert_equal identification.user, event.user
  end

  test "#finish! should preserve a superseded attempt without letting its worker overwrite the new attempt" do
    identification = create(:feed_identification, :no_feed)
    identification.restart_detection
    old_run_id = identification.run_id

    identification.restart_detection
    FeedIdentificationJob.perform_now(identification.id, old_run_id)

    assert_equal 2, events_for(identification).count
    previous = events_for(identification).find_by!("metadata ->> 'run_id' = ?", old_run_id)
    current = events_for(identification).find_by!("metadata ->> 'run_id' = ?", identification.run_id)
    assert_equal "superseded", previous.metadata["status"]
    assert_equal "processing", current.metadata["status"]
  end

  test "#finish! should redact credentials in transport errors" do
    identification = create(:feed_identification, :no_feed)
    stub_request(:get, identification.input).to_raise(SocketError.new("Could not connect to https://name:password@example.com/feed?token=secret#fragment"))

    identification.restart_detection
    FeedIdentificationJob.perform_now(identification.id, identification.run_id)

    metadata = events_for(identification).sole.metadata
    assert_includes metadata.dig("diagnostics", "error", "message"), "https://example.com/feed"
    assert_not_includes metadata.to_json, "password"
    assert_not_includes metadata.to_json, "secret"
    assert_not_includes metadata.to_json, "fragment"
  end

  private

  def events_for(identification)
    Event.where(type: "feed_identification", subject_type: "FeedIdentification", subject_id: identification.id)
  end

  def rss_body
    <<~XML
      <rss version="2.0"><channel><title>Example</title><link>https://example.com</link>
        <item><title>Post</title><link>https://example.com/post</link><description>Private article text</description></item>
      </channel></rss>
    XML
  end
end
