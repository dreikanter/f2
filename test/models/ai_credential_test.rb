require "test_helper"

class AiCredentialTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class ClientCredentialsProvider < LlmProvider::Base
    def credential_errors
      credential_data.values_at("client_id", "client_secret").all?(&:present?) ? [] : ["Enter the client ID and secret"]
    end
  end

  def user
    @user ||= create(:user)
  end

  test "#valid? should return true with a registered provider and an api_key" do
    credential = build(:ai_credential, user: user)
    assert credential.valid?, credential.errors.full_messages.inspect
  end

  test "#valid? should reject an unknown provider" do
    credential = build(:ai_credential, user: user, provider: "made-up")
    refute credential.valid?
    assert_includes credential.errors[:provider], "is not included in the list"
  end

  test "#valid? should reject a blank api_key" do
    credential = build(:ai_credential, user: user, credential_data: { "api_key" => "" })
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#valid? should reject missing credential_data" do
    credential = build(:ai_credential, user: user, credential_data: {})
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#save should reject an API key array" do
    credential = build(:ai_credential, user: user, credential_data: { "api_key" => ["sk-test-key"] })

    refute credential.save
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#save should reject an API key hash" do
    credential = build(:ai_credential, user: user, credential_data: { "api_key" => { "value" => "sk-test-key" } })

    refute credential.save
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#valid? should let the provider interpret credentials without an API key" do
    config = { display_name: "Client credentials", default_model: "example-model", client_class: ClientCredentialsProvider }
    stub_const(LlmProvider, :PROVIDERS, LlmProvider::PROVIDERS.merge("client_credentials" => config)) do
      credential = build(:ai_credential, provider: "client_credentials",
                                        credential_data: { "client_id" => "example-client", "client_secret" => "example-secret" })

      assert credential.valid?, credential.errors.full_messages.inspect
      assert_instance_of ClientCredentialsProvider, credential.build_llm_client

      credential.credential_data.delete("client_secret")

      assert_not credential.valid?
      assert_includes credential.errors[:base], "Enter the client ID and secret"
      assert_not_requested :any, /./
    end
  end

  test "#valid? should enforce display_name uniqueness per (user, provider)" do
    create(:ai_credential, user: user, provider: "openai", display_name: "Work")
    duplicate = build(:ai_credential, user: user, provider: "openai", display_name: "Work")

    refute duplicate.valid?
    assert_includes duplicate.errors[:display_name], "has already been taken"
  end

  test "#valid? should allow the same display_name across users" do
    create(:ai_credential, user: user, display_name: "Work")
    other = build(:ai_credential, user: create(:user), display_name: "Work")

    assert other.valid?
  end

  test "#save! should encrypt credential_data so the raw column doesn't contain the API key" do
    credential = create(:ai_credential, user: user, credential_data: { "api_key" => "sk-test-secret-12345" })

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credential_data FROM ai_credentials WHERE id = #{ActiveRecord::Base.connection.quote(credential.id)}"
    )
    refute_includes raw.to_s, "sk-test-secret-12345"
    assert_equal "sk-test-secret-12345", credential.reload.credential_data["api_key"]
  end

  test "#default? should return true for the user's default credential" do
    credential = create(:ai_credential, :default, user: user)
    assert credential.default?
  end

  test "#default? should return false when another credential is default" do
    first = create(:ai_credential, :default, user: user, display_name: "first")
    second = create(:ai_credential, user: user, display_name: "second")

    refute second.default?
    assert first.default?
  end

  test "#make_default! should set the user's default credential" do
    first = create(:ai_credential, :default, user: user, display_name: "first")
    second = create(:ai_credential, user: user, display_name: "second")

    second.make_default!

    assert_equal second.id, user.reload.default_ai_credential_id
    refute first.reload.default?
    assert second.reload.default?
  end

  test "#make_default! should work when no default exists yet" do
    credential = create(:ai_credential, user: user)
    credential.make_default!
    assert_equal credential.id, user.reload.default_ai_credential_id
  end

  test "#build_llm_client should use the current key without changing an existing client" do
    credential = create(:ai_credential, user: user, provider: "openai")
    original_key = credential.credential_data.fetch("api_key").dup
    client = credential.build_llm_client

    credential.credential_data["api_key"].replace("replacement-key")
    credential.save!

    assert_instance_of LlmProvider::Openai, client
    assert_equal original_key, client.context.config.openai_api_key
    assert_equal "replacement-key", credential.build_llm_client.context.config.openai_api_key
    assert_not_requested :any, /./
  end

  test "#build_llm_client should provide isolated SDK contexts without retries" do
    first = build(:ai_credential, provider: "openai", credential_data: { "api_key" => "first-key" })
    second = build(:ai_credential, provider: "openai", credential_data: { "api_key" => "second-key" })
    original_key = RubyLLM.config.openai_api_key

    first_context = first.build_llm_client.context
    second_context = second.build_llm_client.context

    assert_equal "first-key", first_context.config.openai_api_key
    assert_equal "second-key", second_context.config.openai_api_key
    assert_equal 0, first_context.config.max_retries
    assert_equal original_key, RubyLLM.config.openai_api_key
    assert_not_requested :any, /./
  end

  test "#destroy! should remove a credential with no dependent feeds" do
    credential = create(:ai_credential, user: user)

    assert_difference("AiCredential.count", -1) do
      credential.destroy!
    end
  end

  test "#destroy! should nullify dependent feeds and disable any feed left enabled" do
    credential = create(:ai_credential, user: user)
    feed = create(:feed,
                  user: user,
                  ai_credential: credential,
                  state: :disabled,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })
    enabled_feed = create(:feed,
                          user: user,
                          ai_credential: credential,
                          state: :disabled,
                          feed_profile_key: "rss",
                          params: { "url" => "http://example.com/other.xml" })
    enabled_feed.update_columns(state: Feed.states[:enabled])

    credential.destroy!

    assert_nil feed.reload.ai_credential_id
    assert_nil enabled_feed.reload.ai_credential_id
    assert_equal "disabled", enabled_feed.reload.state
  end

  test "#supported_models should offer listed models without qualification" do
    credential = build(:ai_credential, provider: "openai",
                                       available_models: [{ "id" => "gpt-5.6-luna" }, { "id" => "unverified-model" }])

    assert_equal ["gpt-5.6-luna", "unverified-model"], credential.supported_models.map { |model| model["id"] }
  end

  test "#supports_model? should be true only for a model in the snapshot" do
    credential = build(:ai_credential, provider: "openai",
                                       available_models: [{ "id" => "gpt-5.6-luna" }])

    assert credential.supports_model?("gpt-5.6-luna")
    assert_not credential.supports_model?("some-other-model")
  end

  test "#supports_model? should be true for a newly listed model" do
    credential = build(:ai_credential, provider: "openai",
                                       available_models: [{ "id" => "unverified-model" }])

    assert credential.supports_model?("unverified-model")
  end

  test "#supports_model? should be false for a blank model id" do
    credential = build(:ai_credential, available_models: [{ "id" => "gpt-5.6-luna" }])

    assert_not credential.supports_model?(nil)
    assert_not credential.supports_model?("")
  end

  test "#default_supported_model should prefer the provider default when supported" do
    credential = build(:ai_credential, provider: "openai",
                                       available_models: [{ "id" => "gpt-5.6-luna" }])

    assert_equal "gpt-5.6-luna", credential.default_supported_model
  end

  test "#default_supported_model should choose the first listed model when the default is absent" do
    credential = build(:ai_credential, provider: "openai",
                                       available_models: [{ "id" => "unverified-model" }])

    assert_equal "unverified-model", credential.default_supported_model
  end

  test "#deactivate! should persist the error and create a warning event" do
    credential = create(:ai_credential, :active, user: user)

    assert_difference("Event.count", 1) do
      credential.deactivate!(last_error: "OpenAI: HTTP 401")
    end

    credential.reload
    event = Event.order(:created_at).last
    assert_not credential.active?
    assert_equal "OpenAI: HTTP 401", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "ai_credential_deactivated", event.type
    assert_equal "warning", event.level
    assert_equal credential, event.subject
    assert_equal user, event.user
  end

  test "#deactivate! should disable feeds running on the credential" do
    credential = create(:ai_credential, :active, user: user)
    enabled = create(:feed, :enabled, user: user, ai_credential: credential)
    draft = create(:feed, :draft, user: user, ai_credential: credential)

    credential.deactivate!

    assert enabled.reload.disabled?
    assert draft.reload.draft?
  end
  test "#supported_models should exclude known non-text models while leaving unknown metadata selectable" do
    credential = build(:ai_credential, available_models: [
      { "id" => "image", "metadata" => { "output_modalities" => ["image"] } },
      { "id" => "text", "metadata" => { "output_modalities" => ["text", "audio"] } },
      { "id" => "unknown" }
    ])
    assert_equal ["text", "unknown"], credential.supported_models.pluck("id")
  end

  test "#refresh_models_async should ignore inactive credentials" do
    credential = create(:ai_credential, :inactive, available_models: [{ "id" => "saved-model" }])
    original = credential.attributes

    assert_no_enqueued_jobs do
      assert_no_difference "OperationRun.count" do
        credential.refresh_models_async(force: true)
      end
    end

    assert_equal original, credential.reload.attributes
  end

  test "#refresh_models_async should ignore a forced refresh during validation" do
    credential = create(:ai_credential, :active)
    validation_run = credential.validate_async(AiCredentialValidationJob)

    assert_no_enqueued_jobs do
      assert_no_difference "OperationRun.count" do
        assert_nil credential.refresh_models_async(force: true)
      end
    end

    assert_predicate validation_run.reload, :running?
    assert_predicate credential.reload, :active?
  end

  test "#refresh_models_async should allow refresh after the validation deadline" do
    credential = create(:ai_credential, :active)
    validation_run = credential.validate_async(AiCredentialValidationJob)

    travel_to validation_run.deadline_at do
      assert_enqueued_with(job: AiModelCatalogRefreshJob) { credential.refresh_models_async }
    end
  end

  test "#refresh_models_async should reuse an active run even for a forced refresh" do
    credential = create(:ai_credential, :active)
    run = credential.refresh_models_async

    assert_no_enqueued_jobs { assert_equal run, credential.refresh_models_async(force: true) }
  end

  test "#refresh_models_async should wait an hour before retrying automatically" do
    freeze_time do
      credential = create(:ai_credential, :active)
      credential.refresh_models_async.fail!

      assert_no_enqueued_jobs { assert_nil credential.refresh_models_async }

      travel 1.hour
      assert_enqueued_with(job: AiModelCatalogRefreshJob) { credential.refresh_models_async }
    end
  end

  test "#refresh_models_async should allow a forced refresh during the retry delay" do
    credential = create(:ai_credential, :active)
    credential.refresh_models_async.fail!

    assert_enqueued_with(job: AiModelCatalogRefreshJob) { credential.refresh_models_async(force: true) }
  end
end
