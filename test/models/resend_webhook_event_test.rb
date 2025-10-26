require "test_helper"

class ResendWebhookEventTest < ActiveSupport::TestCase
  test "initializes with data hash" do
    data = {
      email_id: "abc123",
      from: "sender@example.com",
      to: ["recipient@example.com"],
      subject: "Test Email",
      created_at: "2024-01-01T00:00:00Z",
      broadcast_id: "broadcast123",
      tags: { category: "test" }
    }

    event = ResendWebhookEvent.new(data)

    assert_equal "abc123", event.email_id
    assert_equal "sender@example.com", event.from
    assert_equal ["recipient@example.com"], event.to
    assert_equal "Test Email", event.subject
    assert_equal "2024-01-01T00:00:00Z", event.created_at
    assert_equal "broadcast123", event.broadcast_id
    assert_equal({ category: "test" }, event.tags)
  end

  test "normalizes to to array" do
    event = ResendWebhookEvent.new({ to: "single@example.com" })

    assert_equal ["single@example.com"], event.to
  end

  test "returns first recipient email" do
    event = ResendWebhookEvent.new({ to: ["first@example.com", "second@example.com"] })

    assert_equal "first@example.com", event.recipient_email
  end

  test "handles missing to field" do
    event = ResendWebhookEvent.new({})

    assert_equal [], event.to
    assert_nil event.recipient_email
  end

  test "defaults tags to empty hash" do
    event = ResendWebhookEvent.new({})

    assert_equal({}, event.tags)
  end

  test "includes bounce data" do
    data = {
      to: ["bounced@example.com"],
      bounce: {
        message: "Address not found",
        subType: "Suppressed",
        type: "Permanent"
      }
    }

    event = ResendWebhookEvent.new(data)

    assert_equal "Address not found", event.bounce[:message]
    assert_equal "Suppressed", event.bounce[:subType]
    assert_equal "Permanent", event.bounce[:type]
  end

  test "includes click data" do
    data = {
      to: ["clicked@example.com"],
      click: {
        ipAddress: "192.168.1.1",
        link: "https://example.com",
        timestamp: "2024-01-01T00:00:00Z",
        userAgent: "Mozilla/5.0"
      }
    }

    event = ResendWebhookEvent.new(data)

    assert_equal "192.168.1.1", event.click[:ipAddress]
    assert_equal "https://example.com", event.click[:link]
  end

  test "includes failed data" do
    data = {
      to: ["failed@example.com"],
      failed: { reason: "Invalid recipient" }
    }

    event = ResendWebhookEvent.new(data)

    assert_equal "Invalid recipient", event.failed[:reason]
  end

  test "raw_data returns compact hash" do
    data = {
      email_id: "abc123",
      to: ["recipient@example.com"],
      subject: "Test"
    }

    event = ResendWebhookEvent.new(data)
    raw = event.raw_data

    assert_equal "abc123", raw[:email_id]
    assert_equal ["recipient@example.com"], raw[:to]
    assert_equal "Test", raw[:subject]
    assert_equal({}, raw[:tags])
    assert_nil raw[:bounce]
    assert_nil raw[:click]
  end

  test "raw_data excludes nil values" do
    event = ResendWebhookEvent.new({ to: ["test@example.com"] })
    raw = event.raw_data

    assert_not raw.key?(:email_id)
    assert_not raw.key?(:from)
    assert_not raw.key?(:subject)
    assert_not raw.key?(:bounce)
  end
end
