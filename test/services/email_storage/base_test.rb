require "test_helper"

class EmailStorage::BaseTest < ActiveSupport::TestCase
  test "#list raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) { storage.list }
  end

  test "#load_email raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) { storage.load_email("test_id") }
  end

  test "#save_email raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) do
      storage.save_email(metadata: {}, text_content: "test")
    end
  end

  test "#email_exists? raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) { storage.email_exists?("test_id") }
  end

  test "#purge raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) { storage.purge }
  end

  test "#ordered_list sorts newest first and tolerates a missing timestamp" do
    newer = Time.parse("2025-01-02T12:00:00+00:00")
    older = Time.parse("2025-01-01T12:00:00+00:00")
    storage = Class.new(EmailStorage::Base) do
      def list
        [
          { id: "a", timestamp: nil },
          { id: "b", timestamp: Time.parse("2025-01-02T12:00:00+00:00") },
          { id: "c", timestamp: Time.parse("2025-01-01T12:00:00+00:00") }
        ]
      end
    end.new

    assert_equal %w[b c a], storage.ordered_list.map { |e| e[:id] }
    assert_equal [newer, older, nil], storage.ordered_list.map { |e| e[:timestamp] }
  end
end
