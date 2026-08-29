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

  test "#perform should use the persisted credential and ignore the legacy argument" do
    user = create(:user)
    search_credential = create(:search_credential, :active, user: user)
    preview = create(:feed_preview, user: user, feed_profile_key: "llm",
                                    params: { "prompt" => "ruby news" },
                                    search_credential: search_credential, run_id: "run-1")

    workflow = Minitest::Mock.new
    workflow.expect(:execute, nil)

    factory = lambda do |record, run_id:, search_credential:|
      assert_equal preview, record
      assert_equal "run-1", run_id
      assert_equal preview.search_credential, search_credential
      workflow
    end

    FeedPreviewWorkflow.stub(:new, factory) do
      FeedPreviewJob.perform_now(preview.id, "run-1", SecureRandom.uuid)
    end

    workflow.verify
  end

  test "#perform should no-op for a missing preview" do
    assert_nothing_raised { FeedPreviewJob.perform_now("00000000-0000-0000-0000-000000000000", "run-x") }
  end

  test "#perform should swallow CredentialMissing" do
    preview = create(:feed_preview, feed_profile_key: "llm",
                     params: { "prompt" => "https://example.com" }, run_id: "run-1")

    FeedPreviewWorkflow.stub(:new, ->(*, **) { raise LlmClient::CredentialMissing, "no credential" }) do
      assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, "run-1") }
    end
  end

  test "#perform should mark the preview failed and not retry when the loader fails" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")

    stub_request(:get, "https://example.com/feed.xml").to_return(status: 500)

    assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, "run-1") }
    assert preview.reload.failed?
  end

  test "#perform should not write results after timeout rotates run_id" do
    preview = create(:feed_preview, :processing, feed_profile_key: "rss",
                                                params: { "url" => "https://example.com/feed.xml" },
                                                run_id: "run-1")
    stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: "unused")
    FeedPreviewTimeoutJob.perform_now(preview.id, "run-1")

    FeedPreviewJob.perform_now(preview.id, "run-1")

    assert_not_requested :get, "https://example.com/feed.xml"
    assert preview.reload.failed?
  end
end
