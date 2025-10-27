require "test_helper"

class EmailStorage::BaseTest < ActiveSupport::TestCase
  test "#list_emails raises NotImplementedError" do
    storage = EmailStorage::Base.new
    assert_raises(NotImplementedError) { storage.list_emails }
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
end
