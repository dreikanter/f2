require "test_helper"

class FileDeliveryTest < ActiveSupport::TestCase
  setup do
    @written_files = {}
    @created_directories = []

    mkdir_p = ->(dir) { @created_directories << dir.to_s }
    write_file = ->(filepath, &block) {
      fake_file = StringIO.new
      block.call(fake_file)
      @written_files[filepath.to_s] = fake_file.string
    }

    @delivery = FileDelivery.new(mkdir_p: mkdir_p, write_file: write_file)
  end

  test "delivers email and saves to file" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test Subject"
      body "Test Body"
    end

    @delivery.deliver!(mail)

    assert_equal 1, @written_files.size
    filepath, content = @written_files.first

    # Filename should contain timestamp and UUID
    assert_match(/\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\.txt$/, filepath)
    assert_includes content, "---"
    assert_includes content, "message_id:"
    assert_includes content, "from: sender@example.com"
    assert_includes content, "to: recipient@example.com"
    assert_includes content, "subject: Test Subject"
    assert_includes content, "multipart: false"
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

    filepath, content = @written_files.first
    assert_includes content, "multipart: true"
    assert_includes content, "TEXT:"
    assert_includes content, "Text version"
    assert_includes content, "HTML:"
    assert_includes content, "<p>HTML version</p>"
  end

  test "uses UUID in filename" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test Subject"
      body "Test"
    end

    @delivery.deliver!(mail)

    filepath = @written_files.keys.first
    # Should have timestamp and UUID
    assert_match(/\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\.txt$/, filepath)
  end

  test "creates directory if it does not exist" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test"
      body "Test"
    end

    @delivery.deliver!(mail)

    assert_equal 1, @created_directories.size
    assert_match(/tmp\/sent_emails$/, @created_directories.first)
  end
end
