require "test_helper"

class FeedDiagnosticsJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def run_report
    job = FeedDiagnosticsJob.new(feed.id)
    run = create(:job_run, job_class: job.class.name, job_id: job.job_id)
    job.perform_now
    run.events.sole.metadata
  end

  test "#perform should report stored AI output and posts without refreshing the feed" do
    credential = create(:ai_credential, :active, user: feed.user)
    feed.update!(feed_profile_key: "llm", params: { "prompt" => "Find an interesting article" },
                 ai_credential: credential, ai_model: "gpt-6-luna")
    chat = create(:llm_chat, user: feed.user, feed: feed, ai_credential: credential)
    chat.messages.create!(role: "user", content: "The prompt used in this run")
    chat.messages.create!(role: "assistant", content: '{"items":[]}', finish_reason: "stop")
    create(:ruby_llm_usage, chat: chat, input_tokens: 123)
    old_import = create(:post, feed: feed, published_at: 1.day.ago, created_at: 2.hours.ago)
    new_import = create(:post, :rejected, feed: feed, published_at: 1.month.ago, created_at: 1.hour.ago)
    create(:feed_entry_uid, feed: feed, uid: old_import.uid)
    create(:post)
    feed_before = feed.reload.attributes

    report = nil
    assert_no_enqueued_jobs { report = run_report }

    assert_equal feed_before, feed.reload.attributes
    assert_equal "Find an interesting article", report.dig("feed", "params", "prompt")
    assert_equal [old_import.id, new_import.id], report["posts"].pluck("id")
    assert_equal [new_import.id, old_import.id], report.dig("post_order", "import_time_desc")
    assert_equal [old_import.id, new_import.id], report.dig("post_order", "source_date_desc")
    assert_equal ["blank_content"], report["posts"].last["validation_errors"]
    assert_equal [old_import.feed_entry_id, new_import.feed_entry_id].sort, report["entries"].pluck("id").sort
    assert_equal old_import.uid, report["imported_uids"].sole["uid"]
    assert_equal ["The prompt used in this run", '{"items":[]}'], report["chats"].sole["messages"].pluck("content")
    assert_equal 123, report["chats"].sole["usage"].sole["input_tokens"]
  end

  test "#perform should include linked refresh events with full error details" do
    error = { "class" => "Loader::Error", "message" => "Search failed", "backtrace" => ["loader.rb:12"] }
    refresh = create(:event, subject: feed, type: "feed_refresh", metadata: { status: "failed", error: error })
    search = create(:event, message: "Search failed", metadata: { error: error })
    refresh.event_references.create!(reference: search)
    create(:event)

    events = run_report["events"]

    assert_equal [refresh.id, search.id].sort, events.pluck("id").sort
    assert_equal error, events.find { |event| event["id"] == refresh.id }.dig("metadata", "error")
    assert_equal "Search failed", events.find { |event| event["id"] == search.id }["message"]
  end

  test "#perform should exclude credential and reasoning data from the report" do
    credential = create(:ai_credential, :active, user: feed.user, credential_data: { "api_key" => "private-credential" })
    chat = create(:llm_chat, user: feed.user, feed: feed, ai_credential: credential)
    chat.messages.create!(role: "assistant", content: '{"items":[]}', thinking_text: "private-reasoning",
                          thinking_signature: "private-signature", raw_reasoning: [{ "data" => "private-raw-reasoning" }])
    create(:event, subject: feed, message: "Rejected sk-example-secret",
                   metadata: { error: { api_key: "nested-credential", authorization: "Bearer test-secret" } })

    report = run_report
    json = report.to_json

    assert_not_includes json, "private-"
    assert_not_includes json, "nested-credential"
    assert_not_includes json, "test-secret"
    assert_equal "Rejected [FILTERED]", report["events"].sole["message"]
    assert_equal '{"items":[]}', report["chats"].sole["messages"].sole["content"]
  end
end
