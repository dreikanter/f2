require "test_helper"

class EmailStorage::FileSystemStorageTest < ActiveSupport::TestCase
  def storage
    @storage ||= EmailStorage::FileSystemStorage.new(storage_dir)
  end

  def storage_dir
    @storage_dir ||= Rails.root.join("tmp", "test_email_storage_#{SecureRandom.hex(8)}")
  end

  setup do
    FileUtils.rm_rf(storage_dir)
    FileUtils.mkdir_p(storage_dir)
  end

  teardown do
    FileUtils.rm_rf(storage_dir)
  end

  test "#initialize validates directory is inside Rails.root/tmp" do
    assert_raises(RuntimeError) do
      EmailStorage::FileSystemStorage.new(Rails.root)
    end
  end

  test "#initialize validates directory is not blank" do
    assert_raises(RuntimeError) do
      EmailStorage::FileSystemStorage.new(Pathname.new(""))
    end
  end

  test "#ordered_list returns empty array when directory does not exist" do
    FileUtils.rm_rf(storage_dir)
    assert_equal [], storage.ordered_list
  end

  test "#ordered_list returns emails sorted by timestamp" do
    uuid1 = SecureRandom.uuid
    uuid2 = SecureRandom.uuid
    time1 = Time.parse("2025-01-01T12:00:00+00:00")
    time2 = Time.parse("2025-01-02T12:00:00+00:00")
    create_test_email(uuid1, "First", timestamp: time1)
    create_test_email(uuid2, "Second", timestamp: time2)

    emails = storage.ordered_list
    assert_equal 2, emails.size
    assert_equal uuid2, emails[0][:id]
    assert_equal uuid1, emails[1][:id]
    assert_equal "Second", emails[0][:subject]
    assert_equal "First", emails[1][:subject]
    assert_equal time2, emails[0][:timestamp]
    assert_equal time1, emails[1][:timestamp]
  end

  test "#ordered_list skips files with invalid filenames" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Valid")
    File.write(storage_dir.join("invalid.yml"), "data")

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#ordered_list skips files with corrupted YAML" do
    valid_uuid = SecureRandom.uuid
    corrupt_uuid = SecureRandom.uuid
    valid_id = "20250101_120000_123_#{valid_uuid}"
    corrupt_id = "20250102_120000_456_#{corrupt_uuid}"

    create_test_email(valid_id, "Valid")
    File.write(storage_dir.join("#{corrupt_id}.yml"), "invalid: yaml: [")

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#load_email returns nil for non-existent email" do
    assert_nil storage.load_email("nonexistent-uuid")
  end

  test "#load_email loads simple email" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    create_test_email(full_id, "Test Subject", "Test Body")

    email = storage.load_email(uuid)
    assert_equal "Test Subject", email[:subject]
    assert_equal "Test Body", email[:body]
    assert_equal false, email[:multipart]
    assert_nil email[:text_part]
  end

  test "#load_email loads multipart email" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    create_multipart_email(full_id, "Multipart", "Text", "<p>HTML</p>")

    email = storage.load_email(uuid)
    assert_equal "Multipart", email[:subject]
    assert_equal true, email[:multipart]
    assert_equal "Text", email[:text_part]
    assert_equal "<p>HTML</p>", email[:html_part]
    assert_equal "", email[:body]
  end

  test "#load_email returns nil for corrupted YAML" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    File.write(storage_dir.join("#{full_id}.yml"), "invalid: yaml: [")
    File.write(storage_dir.join("#{full_id}.txt"), "Content")

    assert_nil storage.load_email(uuid)
  end

  test "#load_email handles missing text file gracefully" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => false
    }
    File.write(storage_dir.join("#{full_id}.yml"), metadata.to_yaml)

    email = storage.load_email(uuid)
    assert_equal "Test", email[:subject]
  end

  test "#save_email creates metadata and text files" do
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => false
    }

    uuid = storage.save_email(metadata: metadata, text_content: "Body")

    assert_match(/\A[0-9a-f\-]{36}\z/, uuid)

    files = Dir.glob(storage_dir.join("*_#{uuid}.*"))
    assert_equal 2, files.size

    yml_file = files.find { |f| f.end_with?(".yml") }
    txt_file = files.find { |f| f.end_with?(".txt") }

    assert yml_file
    assert txt_file
    assert_equal "Body", File.read(txt_file)
  end

  test "#save_email creates HTML file for multipart" do
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => "Test",
      "date" => Time.now,
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => true
    }

    uuid = storage.save_email(metadata: metadata, text_content: "Text", html_content: "<p>HTML</p>")

    assert_match(/\A[0-9a-f\-]{36}\z/, uuid)

    files = Dir.glob(storage_dir.join("*_#{uuid}.*"))
    html_file = files.find { |f| f.end_with?(".html") }

    assert html_file
    assert_equal "<p>HTML</p>", File.read(html_file)
  end

  test "#email_exists? returns true when email exists" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    create_test_email(full_id, "Test")

    assert storage.email_exists?(uuid)
  end

  test "#email_exists? returns false when email does not exist" do
    refute storage.email_exists?("nonexistent-uuid")
  end

  test "#purge deletes all emails" do
    uuid1 = SecureRandom.uuid
    uuid2 = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid1}", "First")
    create_test_email("20250102_120000_456_#{uuid2}", "Second")

    assert_equal 2, storage.ordered_list.size

    storage.purge

    assert_equal 0, storage.ordered_list.size
    assert Dir.exist?(storage_dir)
  end

  private

  def create_test_email(uuid, subject, body = "Body", timestamp: Time.parse("2025-01-01T12:00:00+00:00"))
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.now,
      "timestamp" => timestamp,
      "multipart" => false
    }
    timestamp_str = timestamp.strftime("%Y%m%d_%H%M%S_%L")
    filename = "#{timestamp_str}_#{uuid}"
    File.write(storage_dir.join("#{filename}.yml"), metadata.to_yaml)
    File.write(storage_dir.join("#{filename}.txt"), body)
  end

  def create_multipart_email(uuid, subject, text, html, timestamp: Time.parse("2025-01-01T12:00:00+00:00"))
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => Time.now,
      "timestamp" => timestamp,
      "multipart" => true
    }
    timestamp_str = timestamp.strftime("%Y%m%d_%H%M%S_%L")
    filename = "#{timestamp_str}_#{uuid}"
    File.write(storage_dir.join("#{filename}.yml"), metadata.to_yaml)
    File.write(storage_dir.join("#{filename}.txt"), text)
    File.write(storage_dir.join("#{filename}.html"), html)
  end
end
