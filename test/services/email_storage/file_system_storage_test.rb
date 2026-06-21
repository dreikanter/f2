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

  test "#ordered_list handles emails with a missing timestamp" do
    uuid = SecureRandom.uuid
    File.write(storage_dir.join("legacy_#{uuid}.json"), JSON.generate("subject" => "Legacy", "multipart" => false))
    File.write(storage_dir.join("legacy_#{uuid}.txt"), "Body")

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Legacy", emails.first[:subject]
    # Falls back to the file mtime so the listing can still render a date.
    assert_kind_of Time, emails.first[:timestamp]
  end

  test "#ordered_list falls back to file mtime for an unparseable timestamp" do
    uuid = SecureRandom.uuid
    File.write(
      storage_dir.join("20250101_120000_123_#{uuid}.json"),
      JSON.generate("subject" => "Bad TS", "timestamp" => "not-a-date")
    )

    email = storage.ordered_list.first
    assert_equal "Bad TS", email[:subject]
    assert_kind_of Time, email[:timestamp]
  end

  test "#ordered_list skips files with invalid filenames" do
    uuid = SecureRandom.uuid
    create_test_email(uuid, "Valid")
    File.write(storage_dir.join("invalid.json"), JSON.generate("subject" => "Nope"))

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#ordered_list skips files with corrupted JSON" do
    valid_uuid = SecureRandom.uuid
    corrupt_uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{valid_uuid}", "Valid")
    File.write(storage_dir.join("20250102_120000_456_#{corrupt_uuid}.json"), "{not json")

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#ordered_list skips JSON files that are not objects" do
    valid_uuid = SecureRandom.uuid
    array_uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{valid_uuid}", "Valid")
    File.write(storage_dir.join("20250102_120000_456_#{array_uuid}.json"), "[1,2,3]")

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Valid", emails.first[:subject]
  end

  test "#ordered_list ignores legacy YAML files" do
    json_uuid = SecureRandom.uuid
    yaml_uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{json_uuid}", "Current")
    # A leftover YAML capture from the previous format must not be read.
    File.write(storage_dir.join("20250102_120000_456_#{yaml_uuid}.yml"), { "subject" => "Old" }.to_yaml)

    emails = storage.ordered_list
    assert_equal 1, emails.size
    assert_equal "Current", emails.first[:subject]
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

  test "#load_email parses the date into a time" do
    uuid = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid}", "Test")

    email = storage.load_email(uuid)
    assert_kind_of Time, email[:date]
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

  test "#load_email returns nil for corrupted JSON" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    File.write(storage_dir.join("#{full_id}.json"), "{not json")
    File.write(storage_dir.join("#{full_id}.txt"), "Content")

    assert_nil storage.load_email(uuid)
  end

  test "#load_email returns nil for JSON that is not an object" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    File.write(storage_dir.join("#{full_id}.json"), "[1,2,3]")
    File.write(storage_dir.join("#{full_id}.txt"), "Content")

    assert_nil storage.load_email(uuid)
  end

  test "#load_email handles missing text file gracefully" do
    uuid = SecureRandom.uuid
    full_id = "20250101_120000_123_#{uuid}"
    metadata = {
      "message_id" => "<test@example.com>",
      "subject" => "Test",
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00").iso8601(3),
      "multipart" => false
    }
    File.write(storage_dir.join("#{full_id}.json"), JSON.generate(metadata))

    email = storage.load_email(uuid)
    assert_equal "Test", email[:subject]
  end

  test "#save_email creates JSON metadata and text files" do
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

    json_file = files.find { |f| f.end_with?(".json") }
    txt_file = files.find { |f| f.end_with?(".txt") }

    assert json_file
    assert txt_file
    assert_equal "Body", File.read(txt_file)
  end

  test "#save_email stores times as ISO8601 strings" do
    metadata = {
      "subject" => "Test",
      "date" => Time.parse("2025-01-01T12:00:00+00:00"),
      "timestamp" => Time.parse("2025-01-02T12:00:00+00:00"),
      "multipart" => false
    }

    uuid = storage.save_email(metadata: metadata, text_content: "Body")
    raw = JSON.parse(File.read(Dir.glob(storage_dir.join("*_#{uuid}.json")).first))

    assert_equal "2025-01-01T12:00:00.000+00:00", raw["date"]
    assert_equal "2025-01-02T12:00:00.000+00:00", raw["timestamp"]
  end

  test "#save_email does not raise on a Date value" do
    metadata = {
      "subject" => "Test",
      "date" => Date.new(2025, 1, 1),
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => false
    }

    assert_nothing_raised do
      storage.save_email(metadata: metadata, text_content: "Body")
    end
  end

  test "#save_email persists metadata that can be read back" do
    metadata = {
      "subject" => "Round trip",
      "timestamp" => Time.parse("2025-01-01T12:00:00+00:00"),
      "multipart" => false
    }

    uuid = storage.save_email(metadata: metadata, text_content: "Body")

    assert_equal "Round trip", storage.ordered_list.find { |e| e[:id] == uuid }[:subject]
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

  test "#purge deletes all emails regardless of format" do
    uuid1 = SecureRandom.uuid
    uuid2 = SecureRandom.uuid
    create_test_email("20250101_120000_123_#{uuid1}", "First")
    # A leftover YAML capture must be wiped too.
    File.write(storage_dir.join("20250102_120000_456_#{uuid2}.yml"), { "subject" => "Old" }.to_yaml)

    storage.purge

    assert_equal 0, storage.ordered_list.size
    assert_empty Dir.glob(storage_dir.join("*"))
    assert Dir.exist?(storage_dir)
  end

  private

  def create_test_email(uuid, subject, body = "Body", timestamp: Time.parse("2025-01-01T12:00:00+00:00"))
    filename = write_metadata(uuid, subject, timestamp: timestamp, multipart: false)
    File.write(storage_dir.join("#{filename}.txt"), body)
  end

  def create_multipart_email(uuid, subject, text, html, timestamp: Time.parse("2025-01-01T12:00:00+00:00"))
    filename = write_metadata(uuid, subject, timestamp: timestamp, multipart: true)
    File.write(storage_dir.join("#{filename}.txt"), text)
    File.write(storage_dir.join("#{filename}.html"), html)
  end

  def write_metadata(uuid, subject, timestamp:, multipart:)
    metadata = {
      "message_id" => "<test@example.com>",
      "from" => "sender@example.com",
      "to" => "recipient@example.com",
      "subject" => subject,
      "date" => timestamp.iso8601(3),
      "timestamp" => timestamp.iso8601(3),
      "multipart" => multipart
    }
    filename = "#{timestamp.strftime("%Y%m%d_%H%M%S_%L")}_#{uuid}"
    File.write(storage_dir.join("#{filename}.json"), JSON.generate(metadata))
    filename
  end
end
