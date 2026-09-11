require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: user)
  end

  def models
    [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }]
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

  test "#create should require authentication" do
    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }
    assert_redirected_to new_session_path
  end

  test "#create should build a pending preview and enqueue a job for a fresh request" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } },
             headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_select '[data-key="preview.processing"]'
    assert_select 'turbo-stream[action="replace"][target="feed-preview"] [data-preview-button-target="frame"]'
    preview = user.feed_previews.last
    assert preview.pending?
    assert_equal "rss", preview.feed_profile_key
    assert_equal "http://example.com/feed.xml", preview.params["url"]
  end

  test "#create should summarize the total post count for a ready preview" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
                                      params: { "url" => "http://example.com/feed.xml" })

    post feed_previews_url, params: { profile_key: "rss", "params" => { url: "http://example.com/feed.xml" } }

    assert_response :success
    summary = css_select('[data-key="preview.summary"]').text
    assert_match "We found 1 post in this feed", summary
    assert_no_match(/peek/, summary)
  end

  test "#create should note the preview is a subset when total exceeds shown posts" do
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

  test "#create should clear the pane and create nothing when source is blank" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "rss", "params" => { url: "" } }, headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_no_match(/preview\.success|preview\.processing/, response.body)
  end

  test "#create should render the credential gate for an AI profile without an active credential" do
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

  test "#create should store the chosen providers and model on the preview" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                         ai_credential_id: credential.id, search_credential_id: search_credential.id,
                         ai_model: "claude-sonnet-4-6" }, headers: TURBO_STREAM

    assert_response :success
    assert_match(/AI is browsing the web/, response.body)
    preview = user.feed_previews.sole
    assert_equal credential.id, preview.ai_credential_id
    assert_equal search_credential.id, preview.search_credential_id
    assert_equal "claude-sonnet-4-6", preview.ai_model
  end

  test "#create should not preview an AI profile with a model the provider does not offer" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user, available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: credential.id, ai_model: "made-up-model" },
            headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_select 'turbo-stream[action="update"][target="feed-preview"]'
    assert_select '[data-key="preview.processing"]', count: 0
  end

  test "#create should not preview an AI profile when the credential is not owned by the user" do
    sign_in_as(user)
    create(:ai_credential, :active, user: user, available_models: models)
    stranger_credential = create(:ai_credential, :active, user: create(:user), available_models: models)

    assert_no_difference("FeedPreview.count") do
      assert_no_enqueued_jobs do
        post feed_previews_url, params: { profile_key: "llm", "params" => { prompt: "anything here" },
                             ai_credential_id: stranger_credential.id, ai_model: "claude-sonnet-4-6" },
            headers: TURBO_STREAM
      end
    end
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

  test "#create should render the failed state without restarting a run" do
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

  test "#update should validate the stored identity rather than request overrides" do
    sign_in_as(user)
    stored_credential = create(:ai_credential, :active, user: user, available_models: models)
    replacement = create(:ai_credential, :active, user: user, available_models: models)
    preview = create(:feed_preview, :completed, user: user, feed_profile_key: "llm",
                                                params: { "prompt" => "ruby news" },
                                                ai_credential: stored_credential,
                                                search_credential: search_credential,
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

  test "#update should not reach another user's preview" do
    sign_in_as(user)
    stranger = create(:feed_preview, :completed, user: create(:user), feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })

    patch feed_preview_url(stranger)

    assert_response :not_found
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
end
