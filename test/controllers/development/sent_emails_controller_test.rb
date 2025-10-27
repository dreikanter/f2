require "test_helper"

class Development::SentEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    email_storage.purge
    Rails.application.reload_routes!
  end

  def email_storage
    EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter)
  end

  test "should get index with no emails" do
    get development_sent_emails_path
    assert_response :success
    assert_select "div.alert-info", text: /No emails captured yet/
  end

  test "should get index with emails" do
    uuid1 = SecureRandom.uuid
    uuid2 = SecureRandom.uuid
    create_test_email(uuid1, "Test Subject", "Test email body")
    create_test_email(uuid2, "Another Email", "Another body")

    get development_sent_emails_path
    assert_response :success

    assert_select "a.list-group-item", count: 2
    assert_select "h5", text: "Test Subject"
    assert_select "h5", text: "Another Email"
  end

  test "should show email" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Test Subject", "Test email body")

    get development_sent_email_path(id: uuid)
    assert_response :success
    assert_select "h4", text: "Test Subject"
    assert_select "pre", text: /Test email body/
  end

  test "should redirect when email not found" do
    uuid = SecureRandom.uuid

    get development_sent_email_path(id: uuid)
    assert_redirected_to development_sent_emails_path
    assert_equal "Email not found", flash[:alert]
  end

  test "should reject invalid ID format" do
    invalid_ids = [
      "invalid-format",
      "not-a-uuid",
      "12345",
      "invalid-uuid-format"
    ]

    invalid_ids.each do |invalid_id|
      get development_sent_email_path(id: invalid_id)
      assert_redirected_to development_sent_emails_path
      assert_equal "Invalid email ID", flash[:alert], "Failed for ID: #{invalid_id}"
    end
  end

  test "should purge all emails" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Test", "Body")
    assert_equal 1, email_storage.list_emails.count

    delete purge_development_sent_emails_path
    assert_redirected_to development_sent_emails_path
    assert_equal "All emails purged", flash[:notice]
    assert_equal 0, email_storage.list_emails.count
  end

  test "should show multipart email with tabs" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Multipart", { text: "Text version", html: "<p>HTML version</p>" })

    get development_sent_email_path(id: uuid)
    assert_response :success
    assert_select "button#text-tab", text: "Text"
    assert_select "button#html-tab", text: "HTML"
    assert_select "pre", text: /Text version/
  end

  test "should handle subject with special characters" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Important: Reset your password", "Email body")

    get development_sent_email_path(id: uuid)
    assert_response :success
    assert_select "h4", text: "Important: Reset your password"
  end

  test "should handle purge errors gracefully" do
    email_storage.stub(:purge, -> { raise "Purge failed" }) do
      delete purge_development_sent_emails_path
      assert_redirected_to development_sent_emails_path
      assert_equal "Failed to purge emails: Purge failed", flash[:alert]
    end
  end

  test "should show email when storage returns nil for load but exists check passes" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Test", "Body")

    email_storage.stub(:load_email, nil) do
      get development_sent_email_path(id: uuid)
      assert_redirected_to development_sent_emails_path
      assert_equal "Failed to load email", flash[:alert]
    end
  end

  private

  def create_test_email(uuid, subject, body)
    multipart = body.is_a?(Hash)

    metadata = {
      "message_id" => "<test_#{SecureRandom.hex(8)}@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.parse("2025-01-01T12:00:00+00:00"),
      "timestamp" => Time.current,
      "multipart" => multipart
    }

    text_content = multipart ? body[:text] : body
    html_content = multipart ? body[:html] : nil

    # Manually save with specific UUID for testing
    email_storage.instance_variable_get(:@emails)[uuid] = {
      id: uuid,
      metadata: metadata,
      text_content: text_content,
      html_content: html_content
    }
  end
end
