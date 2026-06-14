require "test_helper"

class LlmCredentialValidationJobTest < ActiveJob::TestCase
  include Turbo::Broadcastable::TestHelper

  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, user: user, state: :pending)
  end

  def stub_health_check(result)
    LlmClient.stub(:for, ->(_) { fake_client(result) }) do
      yield
    end
  end

  def fake_client(result)
    Class.new do
      def initialize(result) = (@result = result)
      define_method(:health_check) do
        case @result
        when Exception then raise @result
        else @result
        end
      end
    end.new(result)
  end

  test "#perform should move credential to active on successful health check" do
    stub_health_check(true) do
      LlmCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "active", credential.state
    assert_not_nil credential.last_validated_at
    assert_nil credential.last_error
  end

  test "#perform should broadcast a refresh to the credential stream when it resolves" do
    assert_turbo_stream_broadcasts(credential, count: 1) do
      stub_health_check(true) do
        LlmCredentialValidationJob.perform_now(credential)
      end
    end
  end

  test "#perform should move credential to inactive and record the error on provider failure" do
    feed = create(:feed, :enabled, user: user, llm_credential: credential)

    stub_health_check(LlmClient::ProviderError.new("invalid api key")) do
      LlmCredentialValidationJob.perform_now(credential)
    end

    credential.reload
    assert_equal "inactive", credential.state
    assert_equal "invalid api key", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "disabled", feed.reload.state
    assert Event.exists?(subject: credential, type: "llm_credential_deactivated")
  end

  test "#perform should move credential to inactive on rate-limit during validation" do
    stub_health_check(LlmClient::RateLimited.new("429")) do
      LlmCredentialValidationJob.perform_now(credential)
    end

    assert_equal "inactive", credential.reload.state
  end
end
