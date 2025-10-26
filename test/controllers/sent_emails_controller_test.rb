require "test_helper"

class SentEmailsControllerTest < ActionDispatch::IntegrationTest
  def emails_dir
    Rails.root.join("tmp", "test_sent_emails")
  end

  setup do
    FileUtils.mkdir_p(emails_dir)

    # Reload routes to include dev routes in test env
    Rails.application.reload_routes!

    # Use test directory via environment variable
    ENV["DEV_MAILER_DIR"] = "test_sent_emails"
  end

  teardown do
    FileUtils.rm_rf(emails_dir)
    ENV.delete("DEV_MAILER_DIR")
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
    create_test_email("20250101_120000_123_#{uuid1}.txt", "Test Subject", "Test email body")
    create_test_email("20250101_130000_456_#{uuid2}.txt", "Another Email", "Another body")

    get sent_emails_path
    assert_response :success

    assert_select "a.list-group-item", count: 2
    assert_select "h5", text: "Test Subject"
    assert_select "h5", text: "Another Email"
  end

  test "should show email" do
    uuid = SecureRandom.uuid
    filename = "20250101_120000_123_#{uuid}.txt"
    id = filename.delete_suffix(".txt")
    create_test_email(filename, "Test Subject", "Test email body")

    get sent_email_path(id: id)
    assert_response :success
    assert_select "h4", text: "Test Subject"
    assert_select "pre", text: /Test email body/
  end

  test "should redirect when email not found" do
    get sent_email_path(id: "nonexistent")
    assert_redirected_to sent_emails_path
    assert_equal "Email not found", flash[:alert]
  end

  test "should purge all emails" do
    uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid}.txt", "Test", "Body")
    assert_equal 1, Dir.glob(emails_dir.join("*.txt")).count

    delete purge_sent_emails_path
    assert_redirected_to sent_emails_path
    assert_equal "All emails purged", flash[:notice]
    assert_equal 0, Dir.glob(emails_dir.join("*.txt")).count
  end

  test "should show multipart email with tabs" do
    uuid = SecureRandom.uuid
    filename = "20250101_120000_123_#{uuid}.txt"
    id = filename.delete_suffix(".txt")
    create_test_email(filename, "Multipart", { text: "Text version", html: "<p>HTML version</p>" })

    get sent_email_path(id: id)
    assert_response :success
    assert_select "button#text-tab", text: "Text"
    assert_select "button#html-tab", text: "HTML"
    assert_select "pre", text: /Text version/
  end

  # Note: Routes are only defined in development/test environments,
  # enforced by the conditional in config/routes.rb

  private

  def create_test_email(filename, subject, body)
    # Determine if multipart based on body content
    multipart = body.is_a?(Hash)

    if multipart
      content = <<~EMAIL
        ---
        message_id: <test_#{SecureRandom.hex(8)}@example.com>
        from: sender@example.com
        to: recipient@example.com
        subject: #{subject}
        date: 2025-01-01T12:00:00+00:00
        multipart: true
        ---

        TEXT:
        #{body[:text]}

        HTML:
        #{body[:html]}
      EMAIL
    else
      content = <<~EMAIL
        ---
        message_id: <test_#{SecureRandom.hex(8)}@example.com>
        from: sender@example.com
        to: recipient@example.com
        subject: #{subject}
        date: 2025-01-01T12:00:00+00:00
        multipart: false
        ---

        #{body}
      EMAIL
    end

    File.write(emails_dir.join(filename), content)
  end
end
