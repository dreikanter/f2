require "test_helper"

class FileSystemEmailStorageTest < ActiveSupport::TestCase
  def storage
    @storage ||= FileSystemEmailStorage.new(test_dir)
  end

  def test_dir
    @test_dir ||= Rails.root.join("tmp", "test_email_storage_#{SecureRandom.hex(8)}")
  end

  setup do
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
  end

  teardown do
    FileUtils.rm_rf(test_dir)
  end

  test "#initialize validates directory is inside Rails.root/tmp" do
    assert_raises(RuntimeError) do
      FileSystemEmailStorage.new(Rails.root)
    end
  end

  test "#initialize validates directory is not blank" do
    assert_raises(RuntimeError) do
      FileSystemEmailStorage.new(Pathname.new(""))
    end
  end

  test "#list_emails returns empty array when directory does not exist" do
    FileUtils.rm_rf(test_dir)
    assert_equal [], storage.list_emails
  end

  test "#list_emails returns emails sorted by timestamp" do
    create_test_email("20250101_120000_123_#{SecureRandom.uuid}", "First")
    create_test_email("20250102_120000_456_#{SecureRandom.uuid}", "Second")

    emails = storage.list_emails
    assert_equal 2, emails.size
    assert_equal "First", emails[0][:subject]
    assert_equal "Second", emails[1][:subject]
  end

  test "#list_emails skips files with invalid filenames" do
    create_test_email("20250101_120000_123_#{SecureRandom.uuid}", "Valid")
    File.write(test_dir.join("invalid.yml"), "data")

    emails = storage.list_emails
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#list_emails skips files with corrupted YAML" do
    valid_id = "20250101_120000_123_#{SecureRandom.uuid}"
    corrupt_id = "20250102_120000_456_#{SecureRandom.uuid}"

    create_test_email(valid_id, "Valid")
    File.write(test_dir.join("#{corrupt_id}.yml"), "invalid: yaml: [")

    emails = storage.list_emails
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#load_email returns nil for non-existent email" do
    assert_nil storage.load_email("nonexistent_id")
  end

  test "#load_email loads simple email" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    create_test_email(id, "Test Subject", "Test Body")

    email = storage.load_email(id)
    assert_equal "Test Subject", email[:subject]
    assert_equal "Test Body", email[:body]
    assert_equal false, email[:multipart]
    assert_nil email[:text_part]
  end

  test "#load_email loads multipart email" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    create_multipart_email(id, "Multipart", "Text", "<p>HTML</p>")

    email = storage.load_email(id)
    assert_equal "Multipart", email[:subject]
    assert_equal true, email[:multipart]
    assert_equal "Text", email[:text_part]
    assert_equal "<p>HTML</p>", email[:html_part]
    assert_equal "", email[:body]
  end

  test "#load_email returns nil for corrupted YAML" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    File.write(test_dir.join("#{id}.yml"), "invalid: yaml: [")
    File.write(test_dir.join("#{id}.txt"), "Content")

    assert_nil storage.load_email(id)
  end

  test "#load_email handles missing text file gracefully" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "multipart" => false
    }
    File.write(test_dir.join("#{id}.yml"), metadata.to_yaml)

    email = storage.load_email(id)
    assert_equal "Test", email[:subject]
  end

  test "#save_email creates metadata and text files" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "multipart" => false
    }

    storage.save_email(id, metadata: metadata, text_content: "Body")

    assert File.exist?(test_dir.join("#{id}.yml"))
    assert File.exist?(test_dir.join("#{id}.txt"))
    assert_equal "Body", File.read(test_dir.join("#{id}.txt"))
  end

  test "#save_email creates HTML file for multipart" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "multipart" => true
    }

    storage.save_email(id, metadata: metadata, text_content: "Text", html_content: "<p>HTML</p>")

    assert File.exist?(test_dir.join("#{id}.html"))
    assert_equal "<p>HTML</p>", File.read(test_dir.join("#{id}.html"))
  end

  test "#email_exists? returns true when email exists" do
    id = "20250101_120000_123_#{SecureRandom.uuid}"
    create_test_email(id, "Test")

    assert storage.email_exists?(id)
  end

  test "#email_exists? returns false when email does not exist" do
    refute storage.email_exists?("nonexistent_id")
  end

  test "#purge_all deletes all emails" do
    create_test_email("20250101_120000_123_#{SecureRandom.uuid}", "First")
    create_test_email("20250102_120000_456_#{SecureRandom.uuid}", "Second")

    assert_equal 2, storage.list_emails.size

    storage.purge_all

    assert_equal 0, storage.list_emails.size
    assert Dir.exist?(test_dir)
  end

  private

  def create_test_email(id, subject, body = "Body")
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.now,
      "multipart" => false
    }
    File.write(test_dir.join("#{id}.yml"), metadata.to_yaml)
    File.write(test_dir.join("#{id}.txt"), body)
  end

  def create_multipart_email(id, subject, text, html)
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.now,
      "multipart" => true
    }
    File.write(test_dir.join("#{id}.yml"), metadata.to_yaml)
    File.write(test_dir.join("#{id}.txt"), text)
    File.write(test_dir.join("#{id}.html"), html)
  end
end
