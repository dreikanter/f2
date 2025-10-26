require "test_helper"

class ResendWebhooksControllerTest < ActionDispatch::IntegrationTest
  # Generate a valid base64-encoded secret for testing
  WEBHOOK_SECRET = "whsec_#{Base64.strict_encode64('test_secret_key_1234567890')}"

  def user
    @user ||= create(:user, email_address: "test@example.com")
  end

  def user_with_unconfirmed_email
    @user_with_unconfirmed_email ||= create(:user, email_address: "old@example.com", unconfirmed_email: "new@example.com")
  end

  def valid_webhook_payload(type:, data:)
    { type: type, data: data }
  end

  def post_webhook(payload, headers: {})
    Rails.application.credentials.stub(:resend_signing_secret, WEBHOOK_SECRET) do
      payload_json = payload.to_json
      timestamp = Time.now.to_i
      msg_id = "msg_#{SecureRandom.hex(12)}"

      # Use Svix library to sign the payload properly
      wh = Svix::Webhook.new(WEBHOOK_SECRET)
      signature = wh.sign(msg_id, timestamp, payload_json)

      webhook_headers = {
        "svix-id" => msg_id,
        "svix-timestamp" => timestamp.to_s,
        "svix-signature" => signature,
        "Content-Type" => "application/json"
      }.merge(headers)

      post resend_webhooks_url,
           params: payload,
           env: { "RAW_POST_DATA" => payload_json },
           headers: webhook_headers,
           as: :json
    end
  end

  test "should reject request without valid signature" do
    post resend_webhooks_url, params: valid_webhook_payload(type: "email.bounced", data: { to: [user.email_address] })
    assert_response :unauthorized
  end

  test "should accept request with valid signature" do
    post_webhook valid_webhook_payload(type: "email.sent", data: { to: [user.email_address] })

    assert_response :success
  end

  test "email.bounced should deactivate user email for confirmed email" do
    assert_not user.email_deactivated?

    post_webhook valid_webhook_payload(type: "email.bounced", data: { to: [user.email_address] })

    user.reload
    assert user.email_deactivated?
    assert_equal "bounced", user.email_deactivation_reason
  end

  test "email.bounced should create EmailBounced event" do
    assert_difference("Event.where(type: 'EmailBounced').count", 1) do
      post_webhook valid_webhook_payload(type: "email.bounced", data: { to: [user.email_address] })
    end

    event = Event.where(type: "EmailBounced").last
    assert_equal user, event.user
    assert_equal user, event.subject
  end

  test "email.bounced should clear unconfirmed_email for unconfirmed email bounce" do
    assert_equal "new@example.com", user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?

    post_webhook valid_webhook_payload(type: "email.bounced", data: { to: ["new@example.com"] })

    user_with_unconfirmed_email.reload
    assert_nil user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?
  end

  test "email.complained should deactivate user email" do
    post_webhook valid_webhook_payload(type: "email.complained", data: { to: [user.email_address] })

    user.reload
    assert user.email_deactivated?
    assert_equal "complained", user.email_deactivation_reason
  end

  test "email.complained should create EmailComplained event" do
    assert_difference("Event.where(type: 'EmailComplained').count", 1) do
      post_webhook valid_webhook_payload(type: "email.complained", data: { to: [user.email_address] })
    end
  end

  test "email.failed should deactivate user email" do
    post_webhook valid_webhook_payload(type: "email.failed", data: { to: [user.email_address] })

    user.reload
    assert user.email_deactivated?
    assert_equal "failed", user.email_deactivation_reason
  end

  test "email.failed should create EmailFailed event" do
    assert_difference("Event.where(type: 'EmailFailed').count", 1) do
      post_webhook valid_webhook_payload(type: "email.failed", data: { to: [user.email_address] })
    end
  end

  test "email.sent should create EmailSent event" do
    assert_difference("Event.where(type: 'EmailSent').count", 1) do
      post_webhook valid_webhook_payload(type: "email.sent", data: { to: [user.email_address] })
    end
  end

  test "email.delivered should create EmailDelivered event" do
    assert_difference("Event.where(type: 'EmailDelivered').count", 1) do
      post_webhook valid_webhook_payload(type: "email.delivered", data: { to: [user.email_address] })
    end
  end

  test "email.delivery_delayed should create EmailDelayed event" do
    assert_difference("Event.where(type: 'EmailDelayed').count", 1) do
      post_webhook valid_webhook_payload(type: "email.delivery_delayed", data: { to: [user.email_address] })
    end
  end

  test "email.opened should create EmailOpened event" do
    assert_difference("Event.where(type: 'EmailOpened').count", 1) do
      post_webhook valid_webhook_payload(type: "email.opened", data: { to: [user.email_address] })
    end
  end

  test "email.clicked should create EmailClicked event" do
    assert_difference("Event.where(type: 'EmailClicked').count", 1) do
      post_webhook valid_webhook_payload(type: "email.clicked", data: { to: [user.email_address] })
    end
  end

  test "should handle webhook for non-existent user gracefully" do
    assert_no_difference("Event.count") do
      post_webhook valid_webhook_payload(type: "email.bounced", data: { to: ["nonexistent@example.com"] })
    end

    assert_response :success
  end

  test "should normalize email address when finding user" do
    user.update!(email_address: "test@example.com")

    post_webhook valid_webhook_payload(type: "email.bounced", data: { to: ["  TEST@EXAMPLE.COM  "] })

    user.reload
    assert user.email_deactivated?
  end
end
