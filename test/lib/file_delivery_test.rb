require "test_helper"

class FileDeliveryTest < ActiveSupport::TestCase
  def email_storage
    @email_storage ||= EmailStorage::InMemoryStorage.new
  end

  def delivery
    @delivery ||= FileDelivery.new(email_storage: email_storage)
  end

  test "delivers email and saves to storage" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test Subject"
      body "Test Body"
    end

    delivery.deliver!(mail)

    emails = email_storage.list_emails
    assert_equal 1, emails.size

    email = emails.first
    assert_match(/\A[0-9a-f-]{36}\z/, email[:id])
    assert_equal "Test Subject", email[:subject]

    loaded = email_storage.load_email(email[:id])
    assert_equal "sender@example.com", loaded[:from]
    assert_equal "recipient@example.com", loaded[:to]
    assert_equal "Test Subject", loaded[:subject]
    assert_equal false, loaded[:multipart]
    assert_equal "Test Body", loaded[:body]
  end

  test "handles multipart emails" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Multipart Test"

      text_part do
        body "Text version"
      end

      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>HTML version</p>"
      end
    end

    delivery.deliver!(mail)

    emails = email_storage.list_emails
    assert_equal 1, emails.size

    loaded = email_storage.load_email(emails.first[:id])
    assert_equal true, loaded[:multipart]
    assert_equal "Text version", loaded[:text_part]
    assert_equal "<p>HTML version</p>", loaded[:html_part]
  end
end
