require "test_helper"

class EmailStorageAdapterConfigTest < ActiveSupport::TestCase
  test "email_storage_adapter is defined in every environment" do
    # The attribute is set in application.rb so reading it never raises
    # NoMethodError, even in environments that don't override it (staging).
    assert_nothing_raised { Rails.application.config.email_storage_adapter }
    assert_not_nil Rails.application.config.email_storage_adapter
  end
end
