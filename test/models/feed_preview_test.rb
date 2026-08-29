require "test_helper"

class FeedPreviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RUN_ID = "11111111-1111-4111-8111-111111111111"
  NEXT_RUN_ID = "22222222-2222-4222-8222-222222222222"
  AI_RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user)
  end

  test "should belong to user" do
    assert_equal user, feed_preview.user
  end

  test "should optionally belong to a search credential" do
    credential = create(:search_credential, :active, user: user)
    preview = create(:feed_preview, user: user, search_credential: credential)

    assert_equal credential, preview.search_credential
  end

  test "should have feed_profile_key" do
    assert_equal "rss", feed_preview.feed_profile_key
  end

  test "should validate presence of feed_profile_key" do
    preview = build(:feed_preview, feed_profile_key: nil, user: user)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:feed_profile_key, :blank)
  end

  test "should have status enum" do
    preview = create(:feed_preview, user: user)

    assert preview.pending?

    preview.processing!
    assert preview.processing?

    preview.ready!
    assert preview.ready?

    preview.failed!
    assert preview.failed?
  end

  test "#run_id should use the native UUID type" do
    assert_equal :uuid, FeedPreview.type_for_attribute("run_id").type
  end

  test "#posts_data should return empty array when data is nil" do
    preview = create(:feed_preview, user: user, data: nil)
    assert_equal [], preview.posts_data
  end

  test "#posts_data should return empty array when not ready" do
    preview = create(
      :feed_preview,
      user: user,
      status: :pending,
      data: { "posts" => [{ "title" => "Test" }] }
    )

    assert_equal [], preview.posts_data
  end

  test "#posts_data should return posts when ready and data present" do
    posts = [{ "title" => "Test Post" }]

    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => posts }
    )

    assert_equal posts, preview.posts_data
  end

  test "#posts_count should return size of posts_data" do
    posts = [{ "title" => "Test Post 1" }, { "title" => "Test Post 2" }]

    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => posts }
    )

    assert_equal 2, preview.posts_count
  end

  test "#posts_count should return 0 when no posts" do
    preview = create(:feed_preview, user: user, data: nil)
    assert_equal 0, preview.posts_count
  end

  test "#total_entries_count should return recorded total entries" do
    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => [{ "uid" => "1" }], "stats" => { "total_entries" => 42 } }
    )

    assert_equal 42, preview.total_entries_count
  end

  test "#total_entries_count should fall back to posts_count without stats" do
    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => [{ "uid" => "1" }, { "uid" => "2" }] }
    )

    assert_equal 2, preview.total_entries_count
  end

  test "#total_entries_count should return 0 when not ready" do
    preview = create(:feed_preview, user: user, data: nil)
    assert_equal 0, preview.total_entries_count
  end

  test "#timeout! should transition a processing preview to failed" do
    preview = create(:feed_preview, :processing, user: user, run_id: RUN_ID)
    preview.timeout!(run_id: RUN_ID)
    assert preview.failed?
  end

  test "#timeout! should be a no-op for a ready preview" do
    preview = create(:feed_preview, :completed, user: user, run_id: RUN_ID)
    preview.timeout!(run_id: RUN_ID)
    assert preview.ready?
  end

  test "#timeout! should rotate run_id so a stale run can't revive the preview" do
    preview = create(:feed_preview, :processing, user: user, run_id: RUN_ID)

    preview.timeout!(run_id: RUN_ID)

    assert preview.failed?
    assert_not_equal RUN_ID, preview.run_id
    # A late completion from the timed-out run holds the old run_id, so its
    # run_id-gated transition now matches nothing and can't flip it back.
    revived = FeedPreview.where(id: preview.id, run_id: RUN_ID).update_all(status: FeedPreview.statuses[:ready])
    assert_equal 0, revived
    assert preview.reload.failed?
  end

  test "#restart! should schedule the deterministic timeout for the new run" do
    preview = create(:feed_preview, :completed, user: user)

    freeze_time do
      SecureRandom.stub(:uuid, NEXT_RUN_ID) do
        assert_enqueued_with(job: FeedPreviewTimeoutJob, args: [preview.id, NEXT_RUN_ID],
                             at: preview.timeout_after.from_now) do
          preview.restart!
        end
      end
    end
  end

  test "#timeout_after should preserve the deterministic timeout budget" do
    preview = build(:feed_preview, feed_profile_key: "rss")

    assert_equal 85.seconds, preview.timeout_after
    assert_equal 36, preview.polling_max_polls
  end

  test "#restart! should schedule the longer AI timeout budget" do
    preview = create(:feed_preview, :completed, feed_profile_key: "llm")

    assert_equal 4.minutes, preview.timeout_after
    assert_equal 98, preview.polling_max_polls

    freeze_time do
      SecureRandom.stub(:uuid, AI_RUN_ID) do
        assert_enqueued_with(job: FeedPreviewTimeoutJob, args: [preview.id, AI_RUN_ID],
                             at: 4.minutes.from_now) do
          preview.restart!
        end
      end
    end
  end

  test ".digest_for should depend only on the profile's source input" do
    same_source = FeedPreview.digest_for("rss", { "url" => "https://x.test" })
    with_extra = FeedPreview.digest_for("rss", { "url" => "https://x.test", "derived" => "anything" })
    assert_equal same_source, with_extra,
                 "non-source params must not change identity"
  end

  test ".digest_for should differ for different source input" do
    refute_equal FeedPreview.digest_for("rss", { "url" => "https://a.test" }),
                 FeedPreview.digest_for("rss", { "url" => "https://b.test" })
  end

  test ".digest_for should read the source key for the profile's input_shape" do
    prompt_digest = FeedPreview.digest_for("llm", { "prompt" => "rust async" })
    # A url key is ignored for the AI profile; the prompt value drives it.
    assert_equal prompt_digest,
                 FeedPreview.digest_for("llm", { "prompt" => "rust async", "url" => "ignored" })
  end

  test ".digest_for should differ for different models on the same source" do
    params = { "prompt" => "rust async" }
    refute_equal FeedPreview.digest_for("llm", params, 1, "model-a"),
                 FeedPreview.digest_for("llm", params, 1, "model-b")
  end

  test ".digest_for should differ for different credentials on the same source" do
    params = { "prompt" => "rust async" }
    refute_equal FeedPreview.digest_for("llm", params, 1, "model-a"),
                 FeedPreview.digest_for("llm", params, 2, "model-a")
  end

  test ".digest_for should differ for different search credentials on the same source" do
    params = { "prompt" => "rust async" }
    refute_equal FeedPreview.digest_for("llm", params, 1, "model-a", 2),
                 FeedPreview.digest_for("llm", params, 1, "model-a", 3)
  end

  test ".digest_for should match the no-selection default when credential and model are nil" do
    params = { "url" => "https://x.test" }
    assert_equal FeedPreview.digest_for("rss", params),
                 FeedPreview.digest_for("rss", params, nil, nil)
  end
end
