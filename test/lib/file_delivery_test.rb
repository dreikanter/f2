require "test_helper"

class FileDeliveryTest < ActiveSupport::TestCase
  setup do
    @delivery = FileDelivery.new({})
    @sent_emails_dir = Rails.root.join("tmp", "sent_emails")
    FileUtils.rm_rf(@sent_emails_dir)
  end

  test "delivers email and saves to file" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test Subject"
      body "Test Body"
    end

    @delivery.deliver!(mail)

    files = Dir.glob(@sent_emails_dir.join("*.txt"))
    assert_equal 1, files.size

    content = File.read(files.first)
    assert_includes content, "From: sender@example.com"
    assert_includes content, "To: recipient@example.com"
    assert_includes content, "Subject: Test Subject"
    assert_includes content, "Test Body"
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

    @delivery.deliver!(mail)

    files = Dir.glob(@sent_emails_dir.join("*.txt"))
    content = File.read(files.first)

    assert_includes content, "--- TEXT PART ---"
    assert_includes content, "Text version"
    assert_includes content, "--- HTML PART ---"
    assert_includes content, "<p>HTML version</p>"
  end

  test "sanitizes filename" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test/With:Special*Characters?"
      body "Test"
    end

    @delivery.deliver!(mail)

    files = Dir.glob(@sent_emails_dir.join("*.txt"))
    assert_equal 1, files.size
    assert_match(/Test_With_Special_Characters_.txt$/, files.first)
  end

  test "creates directory if it does not exist" do
    FileUtils.rm_rf(@sent_emails_dir)
    refute File.directory?(@sent_emails_dir)

    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test"
      body "Test"
    end

    @delivery.deliver!(mail)

    assert File.directory?(@sent_emails_dir)
  end
end
