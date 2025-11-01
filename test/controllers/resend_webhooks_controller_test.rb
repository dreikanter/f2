require "test_helper"

class ResendWebhooksControllerTest < ActionDispatch::IntegrationTest
  # Generate a valid base64-encoded secret for testing
  WEBHOOK_SECRET = "whsec_#{Base64.strict_encode64('test_secret_key_1234567890')}"

  def user
    @user ||= create(:user, email_address: "test@example.com")
  end

  def post_webhook(payload)
    Rails.application.credentials.stub(:resend_signing_secret, WEBHOOK_SECRET) do
      payload_json = payload.to_json
      timestamp = Time.now.to_i
      msg_id = "msg_#{SecureRandom.hex(12)}"

      webhook = Svix::Webhook.new(WEBHOOK_SECRET)
      signature = webhook.sign(msg_id, timestamp, payload_json)

      headers = {
        "svix-id" => msg_id,
        "svix-timestamp" => timestamp.to_s,
        "svix-signature" => signature,
        "Content-Type" => "application/json"
      }

      post(
        resend_webhooks_url,
        params: payload,
        env: { "RAW_POST_DATA" => payload_json },
        headers: headers,
        as: :json
      )
    end
  end

  test "#create should reject request without valid signature" do
    post resend_webhooks_url, params: { type: "email.bounced", data: { to: [user.email_address] } }
    assert_response :unauthorized
  end

  test "#create should accept request with valid signature" do
    post_webhook(type: "email.sent", data: { to: [user.email_address] })

    assert_response :success
  end

  test "#create should deactivate user email for email.bounced" do
    assert_not user.email_deactivated?

    post_webhook(type: "email.bounced", data: { to: [user.email_address] })

    user.reload

    assert user.email_deactivated?
    assert_equal "bounced", user.email_deactivation_reason
  end

  test "#create should record event for email.bounced" do
    assert_difference -> { Event.where(type: "resend.email.email_bounced").count }, 1 do
      post_webhook(type: "email.bounced", data: { to: [user.email_address] })
    end

    event = Event.where(type: "resend.email.email_bounced").last

    assert_equal user, event.user
    assert_equal user, event.subject
  end

  test "#create should clear unconfirmed email for email.bounced" do
    user_with_unconfirmed_email = create(
      :user,
      email_address: "old@example.com",
      unconfirmed_email: "new@example.com"
    )

    assert_equal "new@example.com", user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?

    post_webhook(type: "email.bounced", data: { to: ["new@example.com"] })

    user_with_unconfirmed_email.reload

    assert_nil user_with_unconfirmed_email.unconfirmed_email
    assert_not user_with_unconfirmed_email.email_deactivated?
  end

  test "#create should deactivate user email for email.complained" do
    post_webhook(type: "email.complained", data: { to: [user.email_address] })

    user.reload
    assert user.email_deactivated?
    assert_equal "complained", user.email_deactivation_reason
  end

  test "#create should record event for email.complained" do
    assert_difference -> { Event.where(type: "resend.email.email_complained").count }, 1 do
      post_webhook(type: "email.complained", data: { to: [user.email_address] })
    end
  end

  test "#create should deactivate user email for email.failed" do
    post_webhook(type: "email.failed", data: { to: [user.email_address] })

    user.reload
    assert user.email_deactivated?
    assert_equal "failed", user.email_deactivation_reason
  end

  test "#create should record event for email.failed" do
    assert_difference -> { Event.where(type: "resend.email.email_failed").count }, 1 do
      post_webhook(type: "email.failed", data: { to: [user.email_address] })
    end
  end

  test "#create should record event for email.sent" do
    assert_difference -> { Event.where(type: "resend.email.email_sent").count }, 1 do
      post_webhook(type: "email.sent", data: { to: [user.email_address] })
    end
  end

  test "#create should record event for email.delivered" do
    assert_difference -> { Event.where(type: "resend.email.email_delivered").count }, 1 do
      post_webhook(type: "email.delivered", data: { to: [user.email_address] })
    end
  end

  test "#create should record event for email.delivery_delayed" do
    assert_difference -> { Event.where(type: "resend.email.email_delayed").count }, 1 do
      post_webhook(type: "email.delivery_delayed", data: { to: [user.email_address] })
    end
  end

  test "#create should record event for email.opened" do
    assert_difference -> { Event.where(type: "resend.email.email_opened").count }, 1 do
      post_webhook(type: "email.opened", data: { to: [user.email_address] })
    end
  end

  test "#create should record event for email.clicked" do
    assert_difference -> { Event.where(type: "resend.email.email_clicked").count }, 1 do
      post_webhook(type: "email.clicked", data: { to: [user.email_address] })
    end
  end

  test "#create should handle webhook for non-existent user gracefully" do
    assert_no_difference("Event.count") do
      post_webhook(type: "email.bounced", data: { to: ["nonexistent@example.com"] })
    end

    assert_response :success
  end

  test "#create should normalize email address when finding user" do
    user.update!(email_address: "test@example.com")

    post_webhook(type: "email.bounced", data: { to: ["  TEST@EXAMPLE.COM  "] })

    user.reload
    assert user.email_deactivated?
  end
end
