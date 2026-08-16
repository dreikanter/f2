require "test_helper"

class ProbesProviderCapabilityTest < ActiveSupport::TestCase
  class UnconfiguredProbeJob < ApplicationJob
    include ProbesProviderCapability

    PROVIDER = "nowhere".freeze
  end

  def user
    @user ||= create(:user)
  end

  test "#credential_for should find the owner's credential for this provider" do
    credential = create(:search_credential, user: user, provider: "serper",
                                            display_name: "SerperCapabilityProbe")

    assert_equal credential, SerperCapabilityProbeJob.credential_for(user)
  end

  test "#credential_for should ignore a credential owned by somebody else" do
    create(:search_credential, provider: "serper", display_name: "SerperCapabilityProbe")

    assert_nil SerperCapabilityProbeJob.credential_for(user)
  end

  test "#missing_credential_message should name the credential and its provider" do
    assert_equal "no search credential named \"SerperCapabilityProbe\" on your account — " \
                 "add a Serper credential with that exact name to run this probe",
                 SerperCapabilityProbeJob.missing_credential_message
    assert_includes AnthropicCapabilityProbeJob.missing_credential_message,
                    "no AI credential named \"AnthropicCapabilityProbe\""
  end

  test "#missing_credential_message should article the provider label correctly" do
    assert_includes AnthropicCapabilityProbeJob.missing_credential_message, "add an Anthropic credential"
    assert_includes BraveCapabilityProbeJob.missing_credential_message, "add a Brave credential"
  end

  test "#runnable_arguments should run the probe on behalf of whoever pressed Run" do
    assert_equal [user], SerperCapabilityProbeJob.runnable_arguments(user)
  end

  test "an including class should implement the credential hooks" do
    assert_raises(NotImplementedError) { UnconfiguredProbeJob.credential_scope(user) }
    assert_raises(NotImplementedError) { UnconfiguredProbeJob.credential_noun }
    assert_raises(NotImplementedError) { UnconfiguredProbeJob.provider_label }
  end
end
