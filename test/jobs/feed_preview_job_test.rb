require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  RUN_ID = "11111111-1111-4111-8111-111111111111"

  test "#perform should run the workflow and finalize the preview" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: RUN_ID)

    workflow = Minitest::Mock.new
    workflow.expect(:execute, nil)

    FeedPreviewWorkflow.stub(:new, ->(p, run_id:) { assert_equal preview, p; assert_equal RUN_ID, run_id; workflow }) do
      FeedPreviewJob.perform_now(preview.id, RUN_ID)
    end

    workflow.verify
  end

  test "#perform should no-op for a missing preview" do
    assert_nothing_raised { FeedPreviewJob.perform_now("00000000-0000-0000-0000-000000000000", RUN_ID) }
  end

  test "#perform should swallow CredentialMissing" do
    preview = create(:feed_preview, feed_profile_key: "llm",
                     params: { "prompt" => "https://example.com" }, run_id: RUN_ID)

    FeedPreviewWorkflow.stub(:new, ->(*, **) { raise LlmClient::CredentialMissing, "no credential" }) do
      assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, RUN_ID) }
    end
  end

  test "#perform should mark the preview failed and not retry when the loader fails" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: RUN_ID)

    stub_request(:get, "https://example.com/feed.xml").to_return(status: 500)

    assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, RUN_ID) }
    assert preview.reload.failed?
  end

  test "#perform should not reopen a settled run on duplicate delivery" do
    feed_url = "https://example.com/feed.xml"
    preview = create(:feed_preview, feed_profile_key: "rss", params: { "url" => feed_url }, run_id: RUN_ID)
    stub_request(:get, feed_url)
      .to_return(status: 200, body: file_fixture("feeds/rss/feed.xml").read,
                 headers: { "Content-Type" => "application/xml" })

    2.times { FeedPreviewJob.perform_now(preview.id, RUN_ID) }

    assert_requested :get, feed_url, times: 1
    assert preview.reload.ready?
  end

  test "#perform should not write results after timeout rotates run_id" do
    preview = create(:feed_preview, :processing, feed_profile_key: "rss",
                                                params: { "url" => "https://example.com/feed.xml" },
                                                run_id: RUN_ID)
    stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: "unused")
    FeedPreviewTimeoutJob.perform_now(preview.id, RUN_ID)

    FeedPreviewJob.perform_now(preview.id, RUN_ID)

    assert_not_requested :get, "https://example.com/feed.xml"
    assert preview.reload.failed?
  end
end
