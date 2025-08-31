require "test_helper"

class ApplicationRecordTest < ActiveSupport::TestCase
  test "should inherit from ActiveRecord::Base" do
    assert ApplicationRecord < ActiveRecord::Base
  end
end
