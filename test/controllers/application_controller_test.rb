require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "should include Authentication concern" do
    assert ApplicationController.include?(Authentication)
  end
end
