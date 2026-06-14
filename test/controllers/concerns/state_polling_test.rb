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

  test "#polling_timeout should trip before the client exhausts its polling budget" do
    timeout_ms = TestController.new.polling_timeout.in_milliseconds
    # First poll is immediate, so the client's last poll lands at (max_polls - 1) * interval.
    last_poll_ms = (TestController.polling_max_polls - 1) * TestController.polling_interval_ms

    assert_operator timeout_ms, :<, last_poll_ms,
      "server must time out before the client's final poll so the outcome renders instead of the spinner freezing"
  end
end
