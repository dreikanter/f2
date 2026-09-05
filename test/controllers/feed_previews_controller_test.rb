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

  test "#create should keep each feed's cached preview separate from unsaved previews" do
    sign_in_as(user)
    first_feed = create(:feed, user: user)
    second_feed = create(:feed, user: user)
    request_params = { profile_key: "rss", "params" => { url: "https://example.com/same.xml" } }
    records = [nil, first_feed, second_feed].map do |feed|
      create(:feed_preview, :completed, user: user, feed: feed,
             feed_profile_key: "rss", params: request_params.fetch("params").stringify_keys)
    end

    assert_no_difference [-> { FeedPreview.count }, -> { Event.count }, -> { LlmUsage.count }] do
      assert_no_enqueued_jobs do
        [nil, first_feed, second_feed].zip(records).each do |feed, record|
          post feed_previews_url, params: request_params.merge(feed_id: feed&.id)

          assert_response :success
          assert_includes response.body, feed_preview_path(record)
        end
      end
    end
  end

  test "#create should associate an owned feed and preserve that association on refresh" do
    sign_in_as(user)
    feed = create(:feed, user: user)
    other_feed = create(:feed, user: user)

    post feed_previews_url, params: { feed_id: feed.id, profile_key: "rss",
                                     "params" => { url: "https://example.com/edited.xml" } }

    assert_response :success
    preview = user.feed_previews.sole
    assert_equal feed, preview.feed
    assert_equal "https://example.com/edited.xml", preview.params["url"]

    patch feed_preview_url(preview), params: { feed_id: other_feed.id }

    assert_response :success
    assert_equal feed, preview.reload.feed
  end

  test "#create should reject another user's feed without starting a preview" do
    sign_in_as(user)
    other_feed = create(:feed)

    assert_no_difference -> { FeedPreview.count } do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { feed_id: other_feed.id, profile_key: "rss",
                                         "params" => { url: "https://example.com/feed.xml" } }
      end
    end

    assert_response :not_found
  end

  test "#show should require authentication" do
    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
    assert_redirected_to new_session_path
  end

  test "#show should build a pending preview and enqueue a job for a fresh request" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
      end
    end

    assert_response :success
    preview = user.feed_previews.last
    assert preview.pending?
    assert_equal "rss", preview.feed_profile_key
    assert_equal "http://example.com/feed.xml", preview.params["url"]
  end

  test "#create should cast a declared option to its type" do
    sign_in_as(user)

    post feed_previews_url,
         params: {
           profile_key: "youtube",
           "params" => { url: "https://www.youtube.com/@chan", exclude_shorts: "1" }
         }

    assert_response :success
    assert_equal true, user.feed_previews.last.params["exclude_shorts"]
  end

  test "#create should drop params the profile doesn't declare" do
    sign_in_as(user)

    post feed_previews_url,
         params: {
           profile_key: "youtube",
           "params" => { url: "https://www.youtube.com/@chan", smuggled: "nope" }
         }

    assert_response :success
    assert_not user.feed_previews.last.params.key?("smuggled")
  end

  test "#show should not enqueue again for an already-ready preview" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
      end
    end

    assert_response :success
  end

  test "#show should summarize the total post count for a ready preview" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }

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

    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }

    assert_response :success
    summary = css_select('[data-key="preview.summary"]').text
    assert_match "We found 25 posts in this feed", summary
    assert_match "peek at the 10 most recent", summary
  end

  test "#show should clear the pane and create nothing when source is blank" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "" } }, headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_no_match(/preview\.success|preview\.processing/, response.body)
  end

  test "#show should render the credential gate for an AI profile without an active credential" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" } },
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
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" } },
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
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6" }
      end
    end

    assert_response :success
  end

  test "#create should store the chosen providers and model on the preview" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)
    search_credential = user.search_credentials.active.first

    post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                         ai_credential_id: credential.id, search_credential_id: search_credential.id,
                         ai_model: "claude-sonnet-4-6" }

    preview = user.feed_previews.last
    assert_equal credential.id, preview.ai_credential_id
    assert_equal search_credential.id, preview.search_credential_id
    assert_equal "claude-sonnet-4-6", preview.ai_model
  end

  test "#create should allow no external search without substituting the user's default" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)
    user.search_credentials.active.first.make_default!

    assert_enqueued_with(job: FeedPreviewJob) do
      post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                                       ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6" }
    end

    assert_response :success
    assert_nil user.feed_previews.last.search_credential_id
  end

  test "#show should keep separate previews for different verified models on the same source" do
    sign_in_as(user)
    anthropic = create(:ai_credential, :active, user: user, available_models: models)
    moonshot = create(:ai_credential, :active, user: user, provider: "moonshot",
                                                available_models: [{ "id" => "kimi-k2.6", "name" => "Kimi K2.6" }])
    source = { prompt: "anything here" }

    assert_difference("FeedPreview.count", 2) do
      post feed_previews_url, params: { profile_key: "llm", "params" => source,
                           ai_credential_id: anthropic.id, ai_model: "claude-sonnet-4-6" }
      post feed_previews_url, params: { profile_key: "llm", "params" => source,
                           ai_credential_id: moonshot.id, ai_model: "kimi-k2.6" }
    end
  end

  test "#show should not preview an AI profile without a selected model" do
    sign_in_as(user)
    create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" } },
            headers: TURBO_STREAM
      end
    end
  end

  test "#show should not preview an AI profile with a model the provider does not offer" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "made-up-model" },
            headers: TURBO_STREAM
      end
    end
  end

  test "#show should preview a newly listed model" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "claude-opus-4-7" },
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
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: stranger_credential.id, ai_model: "claude-opus-4-7" },
            headers: TURBO_STREAM
      end
    end
  end

  test "#create should start a fresh run and enqueue a job" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
      end
    end

    assert_response :success
    assert user.feed_previews.last.pending?
  end

  test "#show should return no content while the preview is still processing" do
    sign_in_as(user)
    preview = create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })

    assert_no_enqueued_jobs do
      get feed_preview_url(preview), headers: TURBO_STREAM
    end

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should render a finished preview" do
    sign_in_as(user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" })

    get feed_preview_url(preview), headers: TURBO_STREAM

    assert_response :success
    assert_match(/data-preview-done/, response.body)
  end

  test "#show should not reach another user's preview" do
    sign_in_as(user)
    stranger = create(:feed_preview, :completed, user: create(:user), feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })

    get feed_preview_url(stranger)

    assert_response :not_found
  end

  test "#create should render the processing pane even though show polls stay silent" do
    sign_in_as(user)

    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
         headers: TURBO_STREAM

    assert_response :success
    assert_match(/data-key="preview.processing"/, response.body)
  end

  # The preview-button Stimulus controller reads this frame as its "frame"
  # target. Since #create replaces the whole frame element, dropping the
  # attribute here would make the controller lose the target after the first
  # preview, silently breaking the button on the next open.
  test "#create should keep the preview-button frame target on the replaced frame" do
    sign_in_as(user)

    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
         headers: TURBO_STREAM

    assert_response :success
    assert_match(/data-preview-button-target="frame"/, response.body)
  end

  test "#show should render the failed state without restarting a run" do
    sign_in_as(user)
    create(:feed_preview, :failed, user: user, feed_profile_key: "rss",
                                   params: { "url" => "http://example.com/feed.xml" })

    assert_no_enqueued_jobs do
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
          headers: TURBO_STREAM
    end

    assert_response :success
    assert_match(/data-preview-done/, response.body)
  end

  test "#update should restart the run and clear the last result" do
    sign_in_as(user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" })

    assert_no_difference("FeedPreview.count") do
      assert_enqueued_with(job: FeedPreviewJob) do
        patch feed_preview_url(preview), headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_match(/data-key="preview.processing"/, response.body)
    preview.reload
    assert preview.pending?
    assert_nil preview.data
  end

  test "#update should rotate the run id so the previous job can't write back" do
    sign_in_as(user)
    preview = create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })
    was = preview.run_id

    patch feed_preview_url(preview), headers: TURBO_STREAM

    refute_equal was, preview.reload.run_id
  end

  test "#update should clear rather than run when the AI credential went inactive" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "llm",
                                                params: { "prompt" => "ruby news" },
                                                ai_credential: credential,
                                                search_credential: user.search_credentials.active.first,
                                                ai_model: "gpt-4o-mini")
    credential.update!(state: :inactive)

    assert_no_enqueued_jobs do
      patch feed_preview_url(preview), headers: TURBO_STREAM
    end

    assert_response :success
    assert preview.reload.ready?, "the stale selection must not start a run"
  end

  test "#update should validate the stored identity rather than request overrides" do
    sign_in_as(user)
    stored_credential = create(:ai_credential, :active, user: user, available_models: models)
    replacement = create(:ai_credential, :active, user: user, available_models: models)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "llm",
                                                params: { "prompt" => "ruby news" },
                                                ai_credential: stored_credential,
                                                search_credential: user.search_credentials.active.first,
                                                ai_model: "claude-sonnet-4-6")
    stored_credential.update!(state: :inactive)

    assert_no_enqueued_jobs do
      patch feed_preview_url(preview),
            params: {
              profile_key: "rss",
              "params" => { "url" => "https://example.com/other.xml" },
              ai_credential_id: replacement.id,
              ai_model: "claude-sonnet-4-6"
            },
            headers: TURBO_STREAM
    end

    assert_response :success
    assert preview.reload.ready?, "request overrides must not bypass the stored selection"
  end

  test "#update should not substitute a different active search credential" do
    sign_in_as(user)
    ai_credential = create(:ai_credential, :active, user: user, available_models: models)
    selected = user.search_credentials.active.first
    create(:search_credential, :active, :default, user: user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "llm",
                                                params: { "prompt" => "ruby news" },
                                                ai_credential: ai_credential,
                                                search_credential: selected,
                                                ai_model: "claude-sonnet-4-6")
    selected.update!(state: :inactive)

    assert_enqueued_jobs 1, only: FeedPreviewJob do
      patch feed_preview_url(preview), headers: TURBO_STREAM
    end

    assert_response :success
    assert preview.reload.pending?
    assert_equal selected.id, preview.search_credential_id
  end

  test "#update should not reach another user's preview" do
    sign_in_as(user)
    stranger = create(:feed_preview, :completed, user: create(:user), feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })

    patch feed_preview_url(stranger)

    assert_response :not_found
  end

  test "#create should reuse a fresh result rather than running again" do
    sign_in_as(user)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" })

    assert_no_enqueued_jobs do
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
           headers: TURBO_STREAM
    end

    assert_response :success
    assert preview.reload.ready?
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
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
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
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
    end

    assert_response :success
  end

  test "#show should not enqueue when ready preview is within the freshness window" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" },
                                      ready_at: 1.minute.ago)

    assert_no_enqueued_jobs do
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
    end

    assert_response :success
  end

  test "#create should render cleared pane for an unknown profile_key" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "nope", "params" => { url: "http://example.com/feed.xml" } },
             headers: TURBO_STREAM
      end
    end

    assert_response :success
  end

  test "#show should not mutate an overdue preview" do
    sign_in_as(user)
    preview = create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" },
                                                run_id: SecureRandom.uuid, updated_at: 10.minutes.ago)
    original_attributes = preview.attributes.slice("status", "run_id", "created_at", "updated_at")

    assert_no_enqueued_jobs do
      get feed_preview_url(preview), headers: TURBO_STREAM
    end

    assert_response :no_content
    assert_equal original_attributes, preview.reload.attributes.slice("status", "run_id", "created_at", "updated_at")
  end

  test "#create should not mutate an overdue preview" do
    sign_in_as(user)
    preview = create(:feed_preview, :processing, user: user, feed_profile_key: "rss",
                                                params: { "url" => "http://example.com/feed.xml" },
                                                run_id: SecureRandom.uuid, updated_at: 10.minutes.ago)
    original_attributes = preview.attributes.slice("status", "run_id", "created_at", "updated_at")

    assert_no_enqueued_jobs do
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
          headers: TURBO_STREAM
    end

    assert_response :success
    assert_equal original_attributes, preview.reload.attributes.slice("status", "run_id", "created_at", "updated_at")
  end

  test "#create should show the AI-browsing copy for an AI preview" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "ruby news" },
                          ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6" },
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
      post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
    end

    assert_response :success
    assert_equal 1, user.feed_previews.count
  end
end
