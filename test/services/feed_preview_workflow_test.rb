require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RUN_ID = "11111111-1111-4111-8111-111111111111"
  NEXT_RUN_ID = "22222222-2222-4222-8222-222222222222"
  AI_RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  FEED_URL = "https://example.com/feed.xml"

  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile_key: "rss",
                             params: { "url" => FEED_URL }, status: :pending, run_id: RUN_ID)
  end

  # Non-ASCII content keeps the body's byte size apart from its character
  # count, so a content_size stat measured in characters fails the stats test.
  def rss_body(items: 1)
    entries = items.times.map do |i|
      <<~XML
        <item>
          <title>Test Post #{i + 1}</title>
          <description>Тестовое содержимое превью</description>
          <link>https://example.com/post#{i + 1}</link>
          <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
          <guid>https://example.com/post#{i + 1}</guid>
        </item>
      XML
    end

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>https://example.com</link>
          #{entries.join}
        </channel>
      </rss>
    XML
  end

  def stub_rss_loader(items: 1)
    stub_request(:get, FEED_URL)
      .to_return(status: 200, body: rss_body(items: items), headers: { "Content-Type" => "application/xml" })
  end

  test "#execute should mark the preview ready with normalized posts and ready_at" do
    stub_rss_loader

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    feed_preview.reload
    assert feed_preview.ready?
    assert feed_preview.ready_at.present?
    assert_equal 1, feed_preview.posts_count
    assert_equal "https://example.com/post1", feed_preview.posts_data.first["source_url"]
  end

  test "#execute should include normalized comments in preview posts" do
    url = "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123def456ghi789jkl"
    preview = create(:feed_preview, user: user, feed_profile_key: "youtube",
                     params: { "url" => url, "include_description" => true },
                     status: :pending, run_id: RUN_ID)
    stub_request(:get, url).to_return(
      status: 200,
      body: file_fixture("feeds/youtube/feed.xml").read,
      headers: { "Content-Type" => "application/atom+xml" }
    )

    FeedPreviewWorkflow.new(preview, run_id: RUN_ID).execute

    comments = preview.reload.posts_data.first["comments"]
    assert_equal 1, comments.size
    assert_includes comments.first, "A beginner-friendly introduction"
  end

  test "#execute should record the stats reported to preview readers" do
    body = rss_body
    stub_request(:get, FEED_URL)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/xml" })

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    stats = feed_preview.reload.data["stats"]
    assert_equal body.bytesize, stats["content_size"]
    assert_equal 1, stats["total_entries"]
    assert_equal 1, stats["preview_entries"]
    assert_equal 1, stats["normalized_posts"]
  end

  test "#execute should cap the preview at PREVIEW_POSTS_LIMIT while reporting the full entry count" do
    total = FeedPreview::PREVIEW_POSTS_LIMIT + 2
    stub_rss_loader(items: total)

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    feed_preview.reload
    assert_equal FeedPreview::PREVIEW_POSTS_LIMIT, feed_preview.posts_count
    assert_equal total, feed_preview.total_entries_count
  end

  test "#execute should mark the preview failed and re-raise when a step fails" do
    stub_request(:get, FEED_URL).to_return(status: 500, body: "")

    workflow = FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID)
    assert_raises(Loader::Error) { workflow.execute }

    assert feed_preview.reload.failed?
    assert_equal :load_feed_contents, workflow.stats[:failed_at_step]
    assert_equal workflow.total_duration, workflow.stats[:total_duration]
  end

  test "#execute should persist AI preview failure details in the activity event" do
    credential = create(:ai_credential, :active, user: user)
    preview = create(:feed_preview, user: user, feed_profile_key: "llm",
                     params: { "prompt" => "A daily roundup" }, ai_credential: credential, ai_model: "gpt-5-nano",
                     status: :pending, run_id: AI_RUN_ID)
    stub_request(:post, "https://api.openai.com/v1/responses").to_timeout

    workflow = FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID)
    error = assert_raises(Loader::Error) { workflow.execute }

    assert preview.reload.failed?
    event = Event.find_by!(type: "feed_preview", subject: credential)
    assert_equal "failed", event.metadata["status"]
    assert_equal error.message, event.message
    assert_equal "Loader::Error", event.metadata.dig("error", "class")
    assert_equal error.message, event.metadata.dig("error", "message")
    assert_equal "load_feed_contents", event.metadata.dig("error", "stage")
    assert_equal error.backtrace, event.metadata.dig("error", "backtrace")
    assert_equal "load_feed_contents", event.metadata.dig("stats", "failed_at_step")
    assert_not event.metadata.fetch("stats").key?("error")
  end

  test "#execute should halt before loading when the run is superseded" do
    preview = create(:feed_preview, user: user, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/superseded.xml" },
                     status: :pending, run_id: NEXT_RUN_ID)

    # No loader stub: a request would raise WebMock::NetConnectNotAllowedError.
    FeedPreviewWorkflow.new(preview, run_id: RUN_ID).execute

    preview.reload
    assert preview.pending?, "expected preview to remain pending (not failed), got #{preview.status}"
    assert_nil preview.data
  end

  test "#execute should process a real AI loader result with the selected model and preview attribution" do
    credential = create(:ai_credential, :active, user: user)
    preview = create(:feed_preview, user: user, feed_profile_key: "llm",
                     params: { "prompt" => "rust async" }, ai_credential: credential,
                     ai_model: "gpt-5-nano", status: :pending, run_id: AI_RUN_ID)
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with { |http| JSON.parse(http.body).fetch("model") == "gpt-5-nano" }
      .to_return_json(body: response)

    assert_no_difference "Feed.count" do
      FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
    end

    chat = LlmChat.sole
    assert chat.succeeded?
    assert_equal user, chat.user
    assert_nil chat.feed_id
    assert_equal credential, chat.ai_credential
    assert_equal "gpt-5-nano", chat.requested_model
    assert_equal "preview", chat.purpose
    assert preview.reload.ready?
    assert_equal '{"items":[]}'.bytesize, preview.data.dig("stats", "content_size")
    event = Event.find_by!(type: "feed_preview", subject: credential)
    assert_equal "completed", event.metadata["status"]
    assert_equal [chat], event.references
    assert_requested request, times: 1
  end

  test "#execute should attribute a saved feed preview and RubyLLM usage to its chat" do
    feed = create(:feed, user: user, feed_profile_key: "llm", params: { "prompt" => "rust async" },
                  ai_credential: ai_preview.ai_credential, ai_model: "gpt-5-nano", search_credential: nil)
    ai_preview.update!(feed: feed)
    model = RubyLLM::Models.new([]).load_from_json.find("gpt-5-nano", provider: "openai")
    RubyLLM::ActiveRecord::Model.from_llm(model).save!
    response = completed_ai_response
    response["output"].last["content"].first["text"] = {
      items: [{ source_url: "https://example.com/rust", body: "Rust async news" }]
    }.to_json
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      chat = LlmChat.sole
      event = Event.find_by!(type: "feed_preview", subject: feed)
      assert_equal [chat], event.references
      { body: response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    assert_no_difference ["Feed.count", "Post.count"] do
      FeedPreviewWorkflow.new(ai_preview, run_id: AI_RUN_ID).execute
    end

    chat = feed.llm_chats.sole
    assert chat.succeeded?
    assert ai_preview.reload.ready?
    assert_equal "Rust async news - https://example.com/rust", ai_preview.posts_data.sole["content"]
    assert_equal "https://example.com/rust", ai_preview.posts_data.sole["source_url"]
    event = Event.find_by!(type: "feed_preview", subject: feed)
    assert_equal "completed", event.metadata["status"]
    assert_equal [chat], event.references
    usage = chat.ruby_llm_usages.sole
    assert_equal "succeeded", usage.status
    assert_equal chat.messages.last, usage.message
    assert_equal 40, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert usage.total_cost.positive?
    assert_equal 1, event.metadata.dig("stats", "llm_calls")
    assert_equal 0.001, event.metadata.dig("stats", "llm_cost_cents")
  end

  test "#execute should include queue time in the preview extraction deadline" do
    freeze_time do
      preview = ai_preview
      deadline = preview.updated_at + preview.timeout_after
      travel 90.seconds
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return_json(body: completed_ai_response)

      assert_enqueued_with(job: LlmChatTimeoutJob, at: deadline) do
        FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
      end

      chat = LlmChat.sole
      assert_equal deadline, chat.deadline_at
      assert preview.reload.ready?
    end
  end

  test "#execute should reject an expired preview before contacting the provider" do
    freeze_time do
      preview = ai_preview
      travel preview.timeout_after

      error = assert_raises(Loader::Error) do
        FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
      end

      assert_kind_of LlmExecution::DeadlineExceeded, error.cause
      assert preview.reload.failed?
      chat = LlmChat.sole
      assert chat.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_not_requested :any, /./
    end
  end

  test "#execute should retain late usage without publishing after the preview deadline" do
    freeze_time do
      preview = ai_preview
      deadline = preview.updated_at + preview.timeout_after
      travel 90.seconds
      stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel_to deadline
        { body: completed_ai_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      error = assert_raises(Loader::Error) do
        FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
      end

      assert_kind_of LlmExecution::DeadlineExceeded, error.cause
      assert preview.reload.failed?
      assert_nil preview.data
      chat = LlmChat.sole
      assert chat.interrupted?
      assert_equal "succeeded", chat.ruby_llm_usages.sole.status
      event = Event.find_by!(type: "feed_preview", subject: preview.ai_credential)
      assert_equal "failed", event.metadata["status"]
    end
  end

  test "#execute should preserve a timeout job's terminal preview state" do
    freeze_time do
      preview = ai_preview
      deadline = preview.updated_at + preview.timeout_after
      travel 90.seconds
      timed_out_run_id = nil
      stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel_to deadline
        FeedPreviewTimeoutJob.perform_now(preview.id, AI_RUN_ID)
        timed_out_run_id = FeedPreview.find(preview.id).run_id
        { body: completed_ai_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      assert_raises(Loader::Error) do
        FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
      end

      assert preview.reload.failed?
      assert_equal timed_out_run_id, preview.run_id
      assert_nil preview.data
      event = Event.find_by!(type: "feed_preview", subject: preview.ai_credential)
      assert_equal "interrupted", event.metadata["status"]
    end
  end

  test "#execute should retain successful extraction without publishing a superseded run" do
    preview = ai_preview
    next_run_id = nil
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      restarted = FeedPreview.find(preview.id).restart!
      next_run_id = restarted.run_id
      { body: completed_ai_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute

    assert preview.reload.pending?
    assert_equal next_run_id, preview.run_id
    assert_nil preview.data
    assert LlmChat.sole.succeeded?
    event = Event.find_by!(type: "feed_preview", subject: preview.ai_credential)
    assert_equal "interrupted", event.metadata["status"]
  end

  test "#execute should preserve a restarted preview when the old request fails" do
    preview = ai_preview
    next_run_id = nil
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      restarted = FeedPreview.find(preview.id).restart!
      next_run_id = restarted.run_id
      {
        status: 429,
        body: { error: { message: "Rate limited", type: "rate_limit_error" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end

    assert_raises(Loader::Error) do
      FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
    end

    assert preview.reload.pending?
    assert_equal next_run_id, preview.run_id
    assert_nil preview.data
    assert LlmChat.sole.failed?
    event = Event.find_by!(type: "feed_preview", subject: preview.ai_credential)
    assert_equal "interrupted", event.metadata["status"]
  end

  test "#execute should not publish results for a changed preview configuration" do
    preview = ai_preview
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      FeedPreview.find(preview.id).update!(params: { "prompt" => "A different topic" })
      { body: completed_ai_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute

    assert preview.reload.processing?
    assert_equal "A different topic", preview.params["prompt"]
    assert_nil preview.data
    event = Event.find_by!(type: "feed_preview", subject: preview.ai_credential)
    assert_equal "interrupted", event.metadata["status"]
  end

  private

  def ai_preview
    @ai_preview ||= create(:feed_preview, user: user, feed_profile_key: "llm",
                           params: { "prompt" => "rust async" },
                           ai_credential: create(:ai_credential, :active, user: user),
                           ai_model: "gpt-5-nano", status: :pending, run_id: AI_RUN_ID)
  end

  def completed_ai_response
    JSON.parse(file_fixture("llm_transcripts/completed.json").read)
  end
end
