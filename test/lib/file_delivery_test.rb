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

    assert_equal 2, @written_files.size  # .yml and .txt

    # Check metadata file
    yml_file = @written_files.keys.find { |k| k.end_with?(".yml") }
    assert_match(/\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\.yml$/, yml_file)
    yml_content = @written_files[yml_file]
    assert_includes yml_content, "message_id:"
    assert_includes yml_content, "from: sender@example.com"
    assert_includes yml_content, "to: recipient@example.com"
    assert_includes yml_content, "subject: Test Subject"
    assert_includes yml_content, "multipart: false"

    # Check text file
    txt_file = @written_files.keys.find { |k| k.end_with?(".txt") }
    assert_match(/\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\.txt$/, txt_file)
    assert_equal "Test Body", @written_files[txt_file]
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

    assert_equal 3, @written_files.size  # .yml, .txt, and .html

    # Check metadata
    yml_content = @written_files.values.find { |c| c.include?("multipart: true") }
    assert_not_nil yml_content
    assert_includes yml_content, "multipart: true"

    # Check text file
    txt_file = @written_files.keys.find { |k| k.end_with?(".txt") }
    assert_equal "Text version", @written_files[txt_file]

    # Check HTML file
    html_file = @written_files.keys.find { |k| k.end_with?(".html") }
    assert_equal "<p>HTML version</p>", @written_files[html_file]
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
