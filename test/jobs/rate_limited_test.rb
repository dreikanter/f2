require "test_helper"

class RateLimitedTest < ActiveJob::TestCase
  class ThrottledJob < ApplicationJob
    include RateLimited

    def perform
      raise RateLimit::Throttled.new(retry_after: 3)
    end
  end

  test "reschedules the job when throttled within the attempt cap" do
    assert_enqueued_with(job: ThrottledJob) do
      ThrottledJob.perform_now
    end
  end

  test "gives up and reports once the attempt cap is reached" do
    job = ThrottledJob.new
    job.executions = RateLimited::MAX_ATTEMPTS

    reported = []
    Rails.error.stub(:report, ->(error, **) { reported << error }) do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_equal 1, reported.size
    assert_instance_of RateLimit::Throttled, reported.first
  end
end
