require "test_helper"

class ResendWebhookEventTest < ActiveSupport::TestCase
  test "#recipient_email should return first recipient" do
    event = ResendWebhookEvent.new(to: ["first@example.com", "second@example.com"])

    assert_equal "first@example.com", event.recipient_email
  end

  test "#recipient_email should handle string to field" do
    event = ResendWebhookEvent.new(to: "single@example.com")

    assert_equal "single@example.com", event.recipient_email
  end

  test "#recipient_email should be nil when to is missing" do
    event = ResendWebhookEvent.new({})

    assert_nil event.recipient_email
  end

  test "#raw_data should include all provided fields" do
    data = {
      email_id: "abc123",
      from: "sender@example.com",
      to: ["recipient@example.com"],
      subject: "Test Email",
      created_at: "2024-01-01T00:00:00Z",
      broadcast_id: "broadcast123",
      tags: { category: "test" },
      bounce: { type: "Permanent" },
      click: { link: "https://example.com" },
      failed: { reason: "Invalid recipient" }
    }

    raw = ResendWebhookEvent.new(data).raw_data

    assert_equal "abc123", raw[:email_id]
    assert_equal "sender@example.com", raw[:from]
    assert_equal ["recipient@example.com"], raw[:to]
    assert_equal "Test Email", raw[:subject]
    assert_equal "2024-01-01T00:00:00Z", raw[:created_at]
    assert_equal "broadcast123", raw[:broadcast_id]
    assert_equal({ category: "test" }, raw[:tags])
    assert_equal({ type: "Permanent" }, raw[:bounce])
    assert_equal({ link: "https://example.com" }, raw[:click])
    assert_equal({ reason: "Invalid recipient" }, raw[:failed])
  end

  test "#raw_data should exclude nil values" do
    raw = ResendWebhookEvent.new(to: ["test@example.com"]).raw_data

    assert_not raw.key?(:email_id)
    assert_not raw.key?(:from)
    assert_not raw.key?(:subject)
    assert_not raw.key?(:bounce)
    assert_not raw.key?(:click)
    assert_not raw.key?(:failed)
  end

  test "#raw_data should default tags to empty hash" do
    raw = ResendWebhookEvent.new({}).raw_data

    assert_equal({}, raw[:tags])
  end
end
