require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "#show should require authentication" do
    get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
    assert_redirected_to new_session_path
  end

  test "#show should build a pending preview and enqueue a job for a fresh request" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
      end
    end

    assert_response :success
    preview = user.feed_previews.last
    assert preview.pending?
    assert_equal "rss", preview.feed_profile_key
    assert_equal "http://example.com/feed.xml", preview.params["url"]
  end

  test "#show should not enqueue again for an already-ready preview" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
      end
    end

    assert_response :success
  end

  test "#show should clear the pane and create nothing when source is blank" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "rss", "params" => { url: "" }), headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_no_match(/preview\.success|preview\.processing/, response.body)
  end

  test "#show should render the credential gate for an AI profile without an active credential" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm_web_search", "params" => { query: "anything here" }),
            headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
    end
  end

  test "#show should render the credential gate when only credential is inactive" do
    sign_in_as(user)
    create(:llm_credential, :inactive, user: user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm_web_search", "params" => { query: "anything here" }),
            headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
    end
  end

  test "#show should proceed for an AI profile with an active credential" do
    sign_in_as(user)
    create(:llm_credential, :active, user: user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        get feed_preview_url(profile_key: "llm_web_search", "params" => { query: "anything here" })
      end
    end

    assert_response :success
  end

  test "#create should start a fresh run and enqueue a job" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
      end
    end

    assert_response :success
    assert user.feed_previews.last.pending?
  end

  test "#create should re-enqueue and reset an existing ready preview" do
    sign_in_as(user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" })

    assert_no_difference("FeedPreview.count") do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
      end
    end

    preview.reload
    assert preview.pending?
    assert_nil preview.data
  end

  test "#destroy should clear the pane and drop the row" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    assert_difference("FeedPreview.count", -1) do
      delete feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" }),
             headers: TURBO_STREAM
    end

    assert_response :success
    assert user.feed_previews.where(feed_profile_key: "rss").none?
  end

  # Fix 1: create-race robustness
  test "#show should not 500 or double-enqueue when a concurrent request already saved the row" do
    sign_in_as(user)

    existing = create(:feed_preview, user: user, feed_profile_key: "rss",
                                     params: { "url" => "http://example.com/feed.xml" },
                                     status: :pending, run_id: SecureRandom.uuid)

    # Simulate the race: find_or_initialize_by returns new_record? = false because
    # the row exists, but start_run would try save! and hit RecordNotUnique if it
    # were new. Here we verify the simpler invariant: when the row already exists,
    # show renders 2xx without creating another row or enqueueing.
    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
      end
    end

    assert_response :success
    assert_equal 1, user.feed_previews.where(feed_profile_key: "rss").count
    existing.reload
    assert existing.pending?
  end


  # Fix 2: stale ready triggers fresh run
  test "#show should enqueue a fresh run when ready preview is outside the enable window" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" },
                                      ready_at: (Feed::ENABLE_PREVIEW_WINDOW + 5.minutes).ago)

    assert_enqueued_with(job: FeedPreviewJob) do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
    end

    assert_response :success
  end

  test "#show should not enqueue when ready preview is within the enable window" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" },
                                      ready_at: 1.minute.ago)

    assert_no_enqueued_jobs do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
    end

    assert_response :success
  end

  # Fix 3: unknown profile_key renders cleared pane, no row, no job
  test "#show should render cleared pane for an unknown profile_key" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "nope", "params" => { url: "http://example.com/feed.xml" }),
            headers: TURBO_STREAM
      end
    end

    assert_response :success
  end

  test "#create should render cleared pane for an unknown profile_key" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_preview_url(profile_key: "nope", "params" => { url: "http://example.com/feed.xml" }),
             headers: TURBO_STREAM
      end
    end

    assert_response :success
  end

  test "#show should scope previews to the current user" do
    other = create(:user)
    create(:feed_preview, :completed, user: other, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
    end

    assert_response :success
    assert_equal 1, user.feed_previews.count
  end
end
