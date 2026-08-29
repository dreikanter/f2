require "test_helper"

class StatePollingTest < ActionController::TestCase
  class TestController < ActionController::Base
    include StatePolling
  end

  tests TestController

  test "#polling_interval_ms and #polling_max_polls should expose defaults" do
    assert_equal 2500, TestController.polling_interval_ms
    assert_equal 36, TestController.polling_max_polls
  end
end
