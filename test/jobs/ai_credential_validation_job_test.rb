require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:ai_credential, user: user, state: :pending)
  end

  def stub_available_models(result)
    LlmClient.stub(:for, ->(_) { fake_client(result) }) do
      yield
    end
  end

  def fake_client(result)
    Class.new do
      def initialize(result) = (@result = result)
      define_method(:available_models) do
        case @result
        when Exception then raise @result
        else @result
        end
      end
    end.new(result)
  end

  test "#perform should move credential to active and persist models on success" do
    models = [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }]

    stub_available_models(models) do
      AiCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "active", credential.state
    assert_equal models, credential.available_models
    assert_not_nil credential.last_validated_at
    assert_nil credential.last_error
    assert_nil credential.validation_started_at
    assert_nil credential.validation_run_id
  end

  test "#perform should deactivate the credential and its feeds when the key is rejected" do
    feed = create(:feed, :enabled, user: user, ai_credential: credential)

    stub_available_models(LlmClient::AuthError.new("invalid api key")) do
      AiCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "inactive", credential.state
    assert_equal "invalid api key", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "disabled", feed.reload.state
    assert Event.exists?(subject: credential, type: "ai_credential_deactivated")
  end

  test "#perform should leave feeds running when the provider fails transiently" do
    active = create(:ai_credential, user: user, state: :active)
    feed = create(:feed, :enabled, user: user, ai_credential: active)

    stub_available_models(LlmClient::ProviderError.new("500 upstream")) do
      AiCredentialValidationJob.perform_now(active)
    end

    active.reload
    assert_equal "active", active.state
    assert_equal "500 upstream", active.last_error
    assert_equal "enabled", feed.reload.state
    assert_not Event.exists?(subject: active, type: "ai_credential_deactivated")
  end

  test "#perform should not deactivate on a rate limit during validation" do
    feed = create(:feed, :enabled, user: user, ai_credential: credential)

    stub_available_models(LlmClient::RateLimited.new("429")) do
      AiCredentialValidationJob.perform_now(credential)
    end

    assert_equal "enabled", feed.reload.state
    assert_not Event.exists?(subject: credential, type: "ai_credential_deactivated")
  end

  # The validation page polls silently while a credential is pending or
  # validating, so a transient failure has to leave a state that settles.
  test "#perform should settle a never-active credential rather than leave it polling" do
    stub_available_models(LlmClient::ProviderError.new("500 upstream")) do
      AiCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_predicate credential, :inactive?
    assert_equal "500 upstream", credential.last_error
  end

  # No LlmClient stubbing: goes through the real client so an error the
  # client fails to map to LlmClient::Error would escape the job's rescue
  # and strand the credential in "validating".
  test "#perform should not strand credential in validating when the provider key does not resolve" do
    RubyLLM::Provider.stub(:resolve, nil) do
      AiCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "inactive", credential.state
    assert_match "unknown RubyLLM provider", credential.last_error
  end

  test "#perform should not strand credential in validating when the provider is unreachable" do
    moonshot = create(:ai_credential, user: user, state: :pending, provider: "moonshot",
                      credential_data: { "api_key" => "sk-moon-test" })
    stub_request(:get, "https://api.moonshot.ai/v1/models").to_timeout

    AiCredentialValidationJob.perform_now(moonshot)

    moonshot.reload
    assert_equal "inactive", moonshot.state
    assert_not_nil moonshot.last_error
  end

  test "#perform should not let a superseded run overwrite the credential" do
    current_run_id = SecureRandom.uuid
    credential.update!(state: :validating, validation_started_at: Time.current,
                       validation_run_id: current_run_id)
    original_attributes = credential.attributes.slice(
      "state", "available_models", "validation_started_at", "validation_run_id", "updated_at"
    )

    LlmClient.stub(:for, ->(_) { flunk "stale run reached the provider" }) do
      AiCredentialValidationJob.perform_now(
        credential.id, SecureRandom.uuid, "inactive"
      )
    end

    assert_equal original_attributes, credential.reload.attributes.slice(*original_attributes.keys)
  end

  test "#perform should not revive a run after its timeout" do
    run_id = SecureRandom.uuid
    credential.update!(state: :validating, validation_started_at: 15.minutes.ago,
                       validation_run_id: run_id)
    ProviderCredentialValidationTimeoutJob.perform_now(
      "AiCredential", credential.id, run_id, "inactive"
    )

    LlmClient.stub(:for, ->(_) { flunk "timed-out run reached the provider" }) do
      AiCredentialValidationJob.perform_now(credential.id, run_id, "inactive")
    end

    assert credential.reload.inactive?
    assert_nil credential.validation_run_id
  end
end
