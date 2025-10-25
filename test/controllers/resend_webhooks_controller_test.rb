require "test_helper"

class ResendWebhooksControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Store original method before any stubbing
    ResendWebhooksController.class_eval do
      unless method_defined?(:verify_signature_original!)
        alias_method :verify_signature_original!, :verify_signature!
      end
    end
  end

  def teardown
    # Restore original method after each test
    ResendWebhooksController.class_eval do
      alias_method :verify_signature!, :verify_signature_original!
    end
  end

  def user
    @user ||= create(:user, email_address: "test@example.com")
  end

  def user_with_unconfirmed_email
    @user_with_unconfirmed_email ||= create(:user, email_address: "old@example.com", unconfirmed_email: "new@example.com")
  end

  def valid_webhook_payload(type:, data:)
    { type: type, data: data }
  end

  def stub_signature_verification
    # Skip signature verification for tests by stubbing the method
    ResendWebhooksController.class_eval do
      def verify_signature!
        # Skip verification in tests
      end
    end
  end

  test "should reject request without valid signature" do
    post resend_webhooks_url, params: valid_webhook_payload(type: "email.bounced", data: { email: user.email_address })
    assert_response :unauthorized
  end

  test "should accept request with valid signature" do
    stub_signature_verification

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.sent", data: { to: user.email_address }),
         as: :json

    assert_response :success
  end

  test "email.bounced should deactivate user email for confirmed email" do
    stub_signature_verification

    assert_not user.email_deactivated?

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.bounced", data: { email: user.email_address }),
         as: :json

    user.reload
    assert user.email_deactivated?
    assert_equal "bounced", user.email_deactivation_reason
  end

  test "email.bounced should create EmailBouncedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailBouncedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.bounced", data: { email: user.email_address }),
           as: :json
    end

    event = Event.where(type: "EmailBouncedEvent").last
    assert_equal user, event.user
    assert_equal user, event.subject
  end

  test "email.bounced should clear unconfirmed_email for unconfirmed email bounce" do
    stub_signature_verification

    assert_equal "new@example.com", user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.bounced", data: { email: "new@example.com" }),
         as: :json

    user_with_unconfirmed_email.reload
    assert_nil user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?
  end

  test "email.complained should deactivate user email" do
    stub_signature_verification

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.complained", data: { email: user.email_address }),
         as: :json

    user.reload
    assert user.email_deactivated?
    assert_equal "complained", user.email_deactivation_reason
  end

  test "email.complained should create EmailComplainedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailComplainedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.complained", data: { email: user.email_address }),
           as: :json
    end
  end

  test "email.failed should deactivate user email" do
    stub_signature_verification

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.failed", data: { email: user.email_address }),
         as: :json

    user.reload
    assert user.email_deactivated?
    assert_equal "failed", user.email_deactivation_reason
  end

  test "email.failed should create EmailFailedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailFailedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.failed", data: { email: user.email_address }),
           as: :json
    end
  end

  test "email.sent should create EmailSentEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailSentEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.sent", data: { to: user.email_address }),
           as: :json
    end
  end

  test "email.delivered should create EmailDeliveredEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailDeliveredEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.delivered", data: { email: user.email_address }),
           as: :json
    end
  end

  test "email.delivery_delayed should create EmailDelayedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailDelayedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.delivery_delayed", data: { email: user.email_address }),
           as: :json
    end
  end

  test "email.opened should create EmailOpenedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailOpenedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.opened", data: { email: user.email_address }),
           as: :json
    end
  end

  test "email.clicked should create EmailClickedEvent" do
    stub_signature_verification

    assert_difference("Event.where(type: 'EmailClickedEvent').count", 1) do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.clicked", data: { email: user.email_address }),
           as: :json
    end
  end

  test "should handle webhook for non-existent user gracefully" do
    stub_signature_verification

    assert_no_difference("Event.count") do
      post resend_webhooks_url,
           params: valid_webhook_payload(type: "email.bounced", data: { email: "nonexistent@example.com" }),
           as: :json
    end

    assert_response :success
  end

  test "should normalize email address when finding user" do
    stub_signature_verification
    user.update!(email_address: "test@example.com")

    post resend_webhooks_url,
         params: valid_webhook_payload(type: "email.bounced", data: { email: "  TEST@EXAMPLE.COM  " }),
         as: :json

    user.reload
    assert user.email_deactivated?
  end
end
