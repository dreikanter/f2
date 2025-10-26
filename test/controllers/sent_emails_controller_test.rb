require "test_helper"

class SentEmailsControllerTest < ActionDispatch::IntegrationTest
  def emails_dir
    Rails.root.join("tmp", "sent_emails")
  end

  setup do
    # Clean and create emails directory
    FileUtils.rm_rf(emails_dir)
    FileUtils.mkdir_p(emails_dir)

    # Reload routes to include dev routes in test env
    Rails.application.reload_routes!
  end

  teardown do
    FileUtils.rm_rf(emails_dir)
  end

  test "should get index with no emails" do
    get sent_emails_path
    assert_response :success
    assert_select "div.alert-info", text: /No emails captured yet/
  end

  test "should get index with emails" do
    # Create test email files
    uuid1 = SecureRandom.uuid
    uuid2 = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid1}", "Test Subject", "Test email body")
    create_test_email("20250101_130000_456_#{uuid2}", "Another Email", "Another body")

    get sent_emails_path
    assert_response :success

    assert_select "a.list-group-item", count: 2
    assert_select "h5", text: "Test Subject"
    assert_select "h5", text: "Another Email"
  end

  test "should show email" do
    uuid = SecureRandom.uuid
    id = "20250101_120000_123_#{uuid}"
    create_test_email(id, "Test Subject", "Test email body")

    get sent_email_path(id: id)
    assert_response :success
    assert_select "h4", text: "Test Subject"
    assert_select "pre", text: /Test email body/
  end

  test "should redirect when email not found" do
    uuid = SecureRandom.uuid
    valid_id = "20250101_120000_123_#{uuid}"

    get sent_email_path(id: valid_id)
    assert_redirected_to sent_emails_path
    assert_equal "Email not found", flash[:alert]
  end

  test "should reject invalid ID format" do
    invalid_ids = [
      "invalid-format",
      "20250101_120000_123",  # Missing UUID
      "not-a-timestamp_#{SecureRandom.uuid}",
      "12345678_123456_123_invalid-uuid-format",
      "20250101_120000_abc_#{SecureRandom.uuid}"  # Invalid milliseconds
    ]

    invalid_ids.each do |invalid_id|
      get sent_email_path(id: invalid_id)
      assert_redirected_to sent_emails_path
      assert_equal "Invalid email ID", flash[:alert], "Failed for ID: #{invalid_id}"
    end
  end

  test "should purge all emails" do
    uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid}", "Test", "Body")
    assert_equal 1, Dir.glob(emails_dir.join("*.yml")).count

    delete purge_sent_emails_path
    assert_redirected_to sent_emails_path
    assert_equal "All emails purged", flash[:notice]
    assert_equal 0, Dir.glob(emails_dir.join("*.yml")).count
  end

  test "should show multipart email with tabs" do
    uuid = SecureRandom.uuid
    id = "20250101_120000_123_#{uuid}"
    create_test_email(id, "Multipart", { text: "Text version", html: "<p>HTML version</p>" })

    get sent_email_path(id: id)
    assert_response :success
    assert_select "button#text-tab", text: "Text"
    assert_select "button#html-tab", text: "HTML"
    assert_select "pre", text: /Text version/
  end

  test "should handle subject with special characters" do
    uuid = SecureRandom.uuid
    id = "20250101_120000_123_#{uuid}"
    create_test_email(id, "Important: Reset your password", "Email body")

    get sent_email_path(id: id)
    assert_response :success
    assert_select "h4", text: "Important: Reset your password"
  end

  # Note: Routes are only defined in development/test environments
  # via the conditional in config/routes.rb

  private

  def create_test_email(base_name, subject, body)
    # Determine if multipart based on body content
    multipart = body.is_a?(Hash)

    # Create metadata (same as FileDelivery)
    metadata = {
      "message_id" => "<test_#{SecureRandom.hex(8)}@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => multipart
    }

    # Write metadata file
    File.write(emails_dir.join("#{base_name}.yml"), metadata.to_yaml)

    # Write text file
    text_content = multipart ? body[:text] : body
    File.write(emails_dir.join("#{base_name}.txt"), text_content)

    # Write HTML file if multipart
    if multipart
      File.write(emails_dir.join("#{base_name}.html"), body[:html])
    end
  end
end
