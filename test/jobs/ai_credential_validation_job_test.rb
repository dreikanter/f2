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
  end

  test "#perform should move credential to inactive and record the error on provider failure" do
    feed = create(:feed, :enabled, user: user, ai_credential: credential)

    stub_available_models(LlmClient::ProviderError.new("invalid api key")) do
      AiCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "inactive", credential.state
    assert_equal "invalid api key", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "disabled", feed.reload.state
    assert Event.exists?(subject: credential, type: "ai_credential_deactivated")
  end

  test "#perform should move credential to inactive on rate-limit during validation" do
    stub_available_models(LlmClient::RateLimited.new("429")) do
      AiCredentialValidationJob.perform_now(credential)
    end

    assert_equal "inactive", credential.reload.state
  end
end
