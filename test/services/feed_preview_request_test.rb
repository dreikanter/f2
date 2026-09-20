require "test_helper"

class FeedPreviewRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def ai_credential
    @ai_credential ||= create(:ai_credential, :active, user: user)
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: user)
  end

  def source
    { "url" => "https://example.com/feed.xml" }
  end

  def ai_attributes
    { profile_key: "llm", params: { prompt: "Sample news" },
      ai_credential_id: ai_credential.id, ai_model: "sample-model" }
  end

  def request(**attributes)
    FeedPreviewRequest.new(user: user, attributes: { profile_key: "rss", params: source }.merge(attributes))
  end

  test "#create should cast declared options and discard undeclared params" do
    result = request(profile_key: "youtube", params: { url: "https://www.youtube.com/@sample",
                                                      exclude_shorts: "1", smuggled: "nope" }).create

    assert_nil result.error
    assert_equal({ "url" => "https://www.youtube.com/@sample", "exclude_shorts" => true }, result.preview.params)
    assert_predicate result.preview, :pending?
    assert_enqueued_with(job: FeedPreviewJob,
                         args: [result.preview.id, result.preview.run_id, result.preview.params_digest])
  end

  test "#create should reject an invalid response limit before starting a preview" do
    assert_no_difference "FeedPreview.count" do
      assert_no_enqueued_jobs do
        result = request(profile_key: "llm", params: { prompt: "Write stories", max_items: "abc" }).create

        assert_equal :invalid_source, result.error
        assert_nil result.preview
      end
    end
  end

  test "#create should reject an out-of-range response limit before starting a preview" do
    assert_no_enqueued_jobs do
      result = request(profile_key: "llm", params: { prompt: "Write stories", max_items: "11" }).create

      assert_equal :invalid_source, result.error
      assert_nil result.preview
    end
  end

  test "#create should persist the response limit and replace the preview when it changes" do
    create(:llm_model, model_id: "sample-model")
    first = request(**ai_attributes.merge(params: { prompt: "Write stories", max_items: "1" })).create
    second = request(**ai_attributes.merge(params: { prompt: "Write stories", max_items: "2" })).create

    assert_nil first.error
    assert_nil second.error
    assert_equal 1, first.preview.reload.params["max_items"]
    assert_equal 2, second.preview.reload.params["max_items"]
    assert_not_equal first.preview.id, second.preview.id
    assert_not_equal first.preview.params_digest, second.preview.params_digest
  end

  test "#create should omit a blank response limit" do
    create(:llm_model, model_id: "sample-model")
    result = request(**ai_attributes.merge(params: { prompt: "Write stories", max_items: " " })).create

    assert_nil result.error
    assert_equal({ "prompt" => "Write stories" }, result.preview.params)
    assert_equal 10, LlmOutput.new(Feed.new(params: result.preview.params)).max_items
  end

  test "#create should reject an unknown profile without creating a preview" do
    assert_no_difference -> { FeedPreview.count } do
      assert_no_enqueued_jobs do
        assert_equal :invalid_source, request(profile_key: "unknown").create.error
      end
    end
  end

  test "#create should reject blank input before checking AI credentials" do
    assert_no_enqueued_jobs do
      result = request(profile_key: "llm", params: { prompt: "  " }).create

      assert_equal :invalid_source, result.error
      assert_nil result.preview
    end
  end

  test "#create should require an active AI credential" do
    create(:ai_credential, :inactive, user: user)

    result = request(profile_key: "llm", params: { prompt: "Sample news" }).create

    assert_equal :missing_ai_credentials, result.error
    assert_nil result.preview
  end

  test "#create should reject another user's AI credential" do
    create(:llm_model, model_id: "sample-model")
    foreign = create(:ai_credential, :active)

    result = request(**ai_attributes.merge(ai_credential_id: foreign.id)).create

    assert_equal :invalid_ai_selection, result.error
    assert_nil result.preview
  end

  test "#create should reject an inactive selection even when another AI credential is active" do
    create(:llm_model, model_id: "sample-model")
    inactive = create(:ai_credential, :inactive, user: user)

    result = request(**ai_attributes.merge(ai_credential_id: inactive.id)).create

    assert_equal :invalid_ai_selection, result.error
    assert_nil result.preview
  end

  test "#create should require an explicit model selection" do
    create(:llm_model, model_id: "sample-model")
    result = request(**ai_attributes.except(:ai_model)).create

    assert_equal :invalid_ai_selection, result.error
    assert_nil result.preview
  end

  test "#create should reject an unlisted model without a previous selection" do
    create(:llm_model, model_id: "sample-model")
    result = request(**ai_attributes.merge(ai_model: "unlisted-model")).create

    assert_equal :invalid_ai_selection, result.error
    assert_nil result.preview
  end

  test "#create should retain a model previously selected on the user's feed" do
    create(:llm_model, model_id: "sample-model")
    create(:feed, user: user, feed_profile_key: "llm", params: { prompt: "Sample news" },
                  ai_credential: ai_credential, ai_model: "sample-model", search_credential: nil)
    RubyLLM::ActiveRecord::Model.update_all(unlisted_at: Time.current)

    result = request(**ai_attributes).create

    assert_nil result.error
    assert_equal "sample-model", result.preview.ai_model
  end

  test "#create should use the selected search credential" do
    create(:llm_model, model_id: "sample-model")
    result = request(**ai_attributes, search_credential_id: search_credential.id).create

    assert_nil result.error
    assert_equal ai_credential, result.preview.ai_credential
    assert_equal search_credential, result.preview.search_credential
    assert_equal "sample-model", result.preview.ai_model
  end

  test "#create should leave external search unset when no credential was selected" do
    create(:llm_model, model_id: "sample-model")
    search_credential.make_default!

    result = request(**ai_attributes).create

    assert_nil result.error
    assert_nil result.preview.search_credential
  end

  test "#create should inherit the feed's search selection when the selector is omitted" do
    create(:llm_model, model_id: "sample-model")
    feed = create(:feed, user: user, feed_profile_key: "llm", params: { prompt: "Sample news" },
                  ai_credential: ai_credential, ai_model: "sample-model", search_credential: search_credential)

    result = request(**ai_attributes, feed_id: feed.id).create

    assert_nil result.error
    assert_equal search_credential, result.preview.search_credential
  end

  test "#create should honor an explicitly blank search selection without changing the feed" do
    create(:llm_model, model_id: "sample-model")
    feed = create(:feed, user: user, feed_profile_key: "llm", params: { prompt: "Sample news" },
                  ai_credential: ai_credential, ai_model: "sample-model", search_credential: search_credential)

    result = request(**ai_attributes, feed_id: feed.id, search_credential_id: "").create

    assert_nil result.error
    assert_nil result.preview.search_credential
    assert_equal search_credential, feed.reload.search_credential
  end

  test "#create should reject another user's search credential" do
    create(:llm_model, model_id: "sample-model")
    foreign = create(:search_credential, :active)

    assert_raises ActiveRecord::RecordNotFound do
      request(**ai_attributes, search_credential_id: foreign.id).create
    end
  end

  test "#create should retain an inactive search credential" do
    create(:llm_model, model_id: "sample-model")
    search_credential.update!(active: false)

    result = request(**ai_attributes, search_credential_id: search_credential.id).create

    assert_nil result.error
    assert_equal search_credential, result.preview.search_credential
  end

  test "#create should ignore search selections for a non-AI profile" do
    result = request(search_credential_id: search_credential.id).create

    assert_nil result.error
    assert_nil result.preview.search_credential
  end

  test "#create should reject attribution to another user's feed" do
    foreign = create(:feed)

    assert_raises ActiveRecord::RecordNotFound do
      request(feed_id: foreign.id).create
    end
    assert_empty user.feed_previews
  end

  test "#create should keep different saved feeds and unsaved previews separate" do
    first_feed = create(:feed, user: user)
    second_feed = create(:feed, user: user)

    unsaved = request.create.preview
    first = request(feed_id: first_feed.id).create.preview
    second = request(feed_id: second_feed.id).create.preview

    assert_equal 3, user.feed_previews.count
    assert_nil unsaved.feed
    assert_equal first_feed, first.feed
    assert_equal second_feed, second.feed
  end

  test "#create should scope cached previews to the user" do
    foreign = create(:feed_preview, :completed, params: source)

    result = request.create

    assert_equal user, result.preview.user
    assert_not_equal foreign.id, result.preview.id
  end

  test "#create should keep previews for different model selections separate" do
    create(:llm_model, model_id: "sample-model")
    original = request(**ai_attributes).create.preview
    create(:llm_model, model_id: "second-model")

    changed = request(**ai_attributes.merge(ai_model: "second-model")).create.preview

    assert_not_equal original.id, changed.id
    assert_equal "second-model", changed.ai_model
  end

  test "#create should reuse a fresh result" do
    existing = create(:feed_preview, :completed, user: user, params: source)

    assert_no_enqueued_jobs do
      assert_equal existing, request.create.preview
    end
    assert_predicate existing.reload, :ready?
  end

  test "#create should restart an expired result" do
    existing = create(:feed_preview, :completed, user: user, params: source,
                                                ready_at: (FeedPreview::PREVIEW_FRESHNESS_WINDOW + 1.minute).ago)

    assert_enqueued_with(job: FeedPreviewJob) do
      assert_equal existing, request.create.preview
    end
    assert_predicate existing.reload, :pending?
    assert_nil existing.data
  end

  test "#create should preserve a failed result until explicitly refreshed" do
    existing = create(:feed_preview, :failed, user: user, params: source)

    assert_no_enqueued_jobs do
      assert_equal existing, request.create.preview
    end
    assert_predicate existing.reload, :failed?
  end

  test "#create should leave an overdue run to its timeout job" do
    existing = create(:feed_preview, :processing, user: user, params: source,
                                                 run_id: SecureRandom.uuid, updated_at: 10.minutes.ago)
    original_attributes = existing.attributes

    assert_no_enqueued_jobs do
      assert_equal existing, request.create.preview
    end
    assert_equal original_attributes, existing.reload.attributes
  end

  test "#create should recover when a matching preview is inserted after lookup" do
    previews = user.feed_previews
    lookup = previews.method(:find_or_initialize_by)
    winner = nil
    insert_after_lookup = ->(**identity) do
      candidate = lookup.call(**identity)
      winner = create(:feed_preview, user: user, params: source)
      candidate
    end

    # Only the lookup is interleaved; saving the stale candidate reaches the
    # actual unique index, and recovery must leave the transaction usable.
    previews.stub(:find_or_initialize_by, insert_after_lookup) do
      assert_no_enqueued_jobs do
        result = request.create

        assert_nil result.error
        assert_equal winner, result.preview
      end
    end
    assert_equal 1, user.feed_previews.count
  end

  test "#create should replace a cached preview after the profile changes" do
    old_profiles = FeedProfile::PROFILES.deep_dup
    old_profiles["wumo"][:processor] = old_profiles["rss"][:processor]
    old_preview = nil
    stub_const(FeedProfile, :PROFILES, old_profiles) do
      old_preview = create(:feed_preview, :completed, user: user, feed_profile_key: "wumo", params: source)
    end

    result = request(profile_key: "wumo").create

    assert_not_equal old_preview.id, result.preview.id
    assert_predicate result.preview, :pending?
    assert_predicate result.preview, :current_configuration?
  end

  test "#refresh should restart the current configuration when given an obsolete preview" do
    old_profiles = FeedProfile::PROFILES.deep_dup
    old_profiles["wumo"][:processor] = old_profiles["rss"][:processor]
    old_preview = nil
    stub_const(FeedProfile, :PROFILES, old_profiles) do
      old_preview = create(:feed_preview, :completed, user: user, feed_profile_key: "wumo", params: source)
    end
    current = create(:feed_preview, :completed, user: user, feed_profile_key: "wumo", params: source)

    assert_no_difference -> { FeedPreview.count } do
      assert_enqueued_with(job: FeedPreviewJob) do
        assert_equal current, request.refresh(old_preview).preview
      end
    end
    assert_predicate current.reload, :pending?
    assert_nil current.data
  end

  test "#refresh should preserve the stored source and selections" do
    create(:llm_model, model_id: "sample-model")
    feed = create(:feed, user: user)
    existing = create(:feed_preview, :completed, user: user, feed: feed, feed_profile_key: "llm",
                                                params: { "prompt" => "Sample news" }, ai_model: "sample-model",
                                                ai_credential: ai_credential, search_credential: search_credential)
    original_digest = existing.params_digest
    RubyLLM::ActiveRecord::Model.update_all(unlisted_at: Time.current)

    result = request(params: { url: "https://example.com/override.xml" }).refresh(existing)

    assert_nil result.error
    assert_equal existing, result.preview
    assert_equal original_digest, existing.reload.params_digest
    assert_equal feed, existing.feed
    assert_equal "sample-model", existing.ai_model
    assert_equal({ "prompt" => "Sample news" }, existing.params)
  end

  test "#refresh should reject another user's preview" do
    foreign = create(:feed_preview, :completed)

    assert_raises ActiveRecord::RecordNotFound do
      request.refresh(foreign)
    end
  end

  test "#refresh should reject a revoked AI credential despite an active alternative" do
    create(:llm_model, model_id: "sample-model")
    existing = request(**ai_attributes).create.preview
    ai_credential.update!(active: false)
    create(:ai_credential, :active, user: user)

    assert_no_enqueued_jobs do
      result = request.refresh(existing)

      assert_equal :invalid_ai_selection, result.error
      assert_nil result.preview
    end
  end

  test "#refresh should preserve an inactive search selection without substituting the default" do
    create(:llm_model, model_id: "sample-model")
    existing = request(**ai_attributes, search_credential_id: search_credential.id).create.preview
    search_credential.update!(active: false)
    create(:search_credential, :active, :default, user: user)

    assert_enqueued_jobs 1, only: FeedPreviewJob do
      result = request.refresh(existing)

      assert_nil result.error
      assert_equal search_credential, result.preview.search_credential
    end
  end
end
