require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  test "#perform should run the workflow and finalize the preview" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")

    workflow = Minitest::Mock.new
    workflow.expect(:execute, nil)

    FeedPreviewWorkflow.stub(:new, ->(p, run_id:) { assert_equal preview, p; assert_equal "run-1", run_id; workflow }) do
      FeedPreviewJob.perform_now(preview.id, "run-1")
    end

    workflow.verify
  end

  test "#perform should no-op for a missing preview" do
    assert_nothing_raised { FeedPreviewJob.perform_now("00000000-0000-0000-0000-000000000000", "run-x") }
  end

  test "#perform should swallow CredentialMissing" do
    preview = create(:feed_preview, feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" }, run_id: "run-1")

    FeedPreviewWorkflow.stub(:new, ->(*, **) { raise LlmClient::CredentialMissing, "no credential" }) do
      assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, "run-1") }
    end
  end
end
