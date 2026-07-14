require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    create(:search_credential, :active, user: user)
  end

  def user
    @user ||= create(:user)
  end

  def models
    [
      { "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" },
      { "id" => "claude-opus-4-7", "name" => "Claude Opus 4.7" }
    ]
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

  test "#show should summarize the total post count for a ready preview" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })

    assert_response :success
    summary = css_select('[data-key="preview.summary"]').text
    assert_match "We found 1 post in this feed", summary
    assert_no_match(/peek/, summary)
  end

  test "#show should note the preview is a subset when total exceeds shown posts" do
    sign_in_as(user)
    posts = 10.times.map { |i| { "uid" => "uid-#{i}", "content" => "post #{i}" } }
    create(:feed_preview, user: user, status: :ready, ready_at: 1.minute.ago,
                          feed_profile_key: "rss", params: { "url" => "http://example.com/feed.xml" },
                          data: { "posts" => posts, "stats" => { "total_entries" => 25 } })

    get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })

    assert_response :success
    summary = css_select('[data-key="preview.summary"]').text
    assert_match "We found 25 posts in this feed", summary
    assert_match "peek at the 10 most recent", summary
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
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" }),
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
    create(:ai_credential, :inactive, user: user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" }),
            headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_select "[data-key='credentials.gate']" do
      assert_select "button[type='submit'][name='commit'][value='save_as_draft_and_add_credentials']",
                    text: /Add AI credentials/
    end
  end

  test "#show should proceed for an AI profile with a valid credential and available model" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6")
      end
    end

    assert_response :success
  end

  test "#show should store the chosen provider and model on the preview" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" },
                         ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6")

    preview = user.feed_previews.last
    assert_equal credential.id, preview.ai_credential_id
    assert_equal "claude-sonnet-4-6", preview.ai_model
  end

  test "#show should keep separate previews for different verified models on the same source" do
    sign_in_as(user)
    anthropic = create(:ai_credential, :active, user: user, available_models: models)
    moonshot = create(:ai_credential, :active, user: user, provider: "moonshot",
                                                available_models: [{ "id" => "kimi-k2.5", "name" => "Kimi K2.5" }])
    source = { prompt: "anything here" }

    assert_difference("FeedPreview.count", 2) do
      get feed_preview_url(profile_key: "llm", "params" => source,
                           ai_credential_id: anthropic.id, ai_model: "claude-sonnet-4-6")
      get feed_preview_url(profile_key: "llm", "params" => source,
                           ai_credential_id: moonshot.id, ai_model: "kimi-k2.5")
    end
  end

  test "#show should not preview an AI profile without a selected model" do
    sign_in_as(user)
    create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" }),
            headers: TURBO_STREAM
      end
    end
  end

  test "#show should not preview an AI profile with a model the provider does not offer" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "made-up-model"),
            headers: TURBO_STREAM
      end
    end
  end

  test "#show should not preview a model that is offered but not dev-verified" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "claude-opus-4-7"),
            headers: TURBO_STREAM
      end
    end
  end

  test "#show should not preview an AI profile when the credential is not owned by the user" do
    sign_in_as(user)
    create(:ai_credential, :active, user: user, available_models: models)
    stranger_credential = create(:ai_credential, :active, user: create(:user), available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        get feed_preview_url(profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: stranger_credential.id, ai_model: "claude-opus-4-7"),
            headers: TURBO_STREAM
      end
    end
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

  test "#show should return no content while the preview is still processing" do
    sign_in_as(user)
    create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                       params: { "url" => "http://example.com/feed.xml" })

    assert_no_enqueued_jobs do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" }),
          headers: TURBO_STREAM
    end

    assert_response :no_content
    assert_empty response.body
  end

  test "#create should render the processing pane even though show polls stay silent" do
    sign_in_as(user)

    post feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" }),
         headers: TURBO_STREAM

    assert_response :success
    assert_match(/data-key="preview.processing"/, response.body)
  end

  test "#show should render the failed state without restarting a run" do
    sign_in_as(user)
    create(:feed_preview, :failed, user: user, feed_profile_key: "rss",
                                   params: { "url" => "http://example.com/feed.xml" })

    assert_no_enqueued_jobs do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" }),
          headers: TURBO_STREAM
    end

    assert_response :success
    assert_match(/data-preview-done/, response.body)
  end

  test "#create should restart a failed preview and enqueue a job" do
    sign_in_as(user)
    create(:feed_preview, :failed, user: user, feed_profile_key: "rss",
                                   params: { "url" => "http://example.com/feed.xml" })

    assert_no_difference("FeedPreview.count") do
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
  test "#show should enqueue a fresh run when ready preview is outside the freshness window" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" },
                                      ready_at: (FeedPreview::PREVIEW_FRESHNESS_WINDOW + 5.minutes).ago)

    assert_enqueued_with(job: FeedPreviewJob) do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" })
    end

    assert_response :success
  end

  test "#show should not enqueue when ready preview is within the freshness window" do
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

  test "#show should mark a timed-out preview as failed and render the failed partial" do
    sign_in_as(user)
    create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                       params: { "url" => "http://example.com/feed.xml" },
                                       updated_at: 10.minutes.ago)

    assert_no_enqueued_jobs do
      get feed_preview_url(profile_key: "rss", "params" => { url: "http://example.com/feed.xml" }),
          headers: TURBO_STREAM
    end

    assert_response :success
    assert_match(/data-preview-done/, response.body)
    assert user.feed_previews.last.failed?
  end

  test "#show should not time out an AI preview within its longer budget" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)
    create(:feed_preview, :processing, user: user, feed_profile_key: "llm",
                                       params: { "prompt" => "ruby news" },
                                       ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6",
                                       updated_at: 90.seconds.ago)

    assert_no_enqueued_jobs do
      get feed_preview_url(profile_key: "llm", "params" => { prompt: "ruby news" },
                           ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6"),
          headers: TURBO_STREAM
    end

    assert_response :success
    assert_not user.feed_previews.last.failed?, "an AI preview should survive past the deterministic budget"
  end

  test "#show should time out an AI preview past its longer budget" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)
    create(:feed_preview, :processing, user: user, feed_profile_key: "llm",
                                       params: { "prompt" => "ruby news" },
                                       ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6",
                                       updated_at: 5.minutes.ago)

    get feed_preview_url(profile_key: "llm", "params" => { prompt: "ruby news" },
                         ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6"),
        headers: TURBO_STREAM

    assert_response :success
    assert user.feed_previews.last.failed?
  end

  test "#create should show the AI-browsing copy for an AI preview" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    post feed_preview_url(profile_key: "llm", "params" => { prompt: "ruby news" },
                          ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6"),
         headers: TURBO_STREAM

    assert_response :success
    assert_match(/AI is browsing the web/, response.body)
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
