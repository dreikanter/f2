require "test_helper"

class RateLimitedTest < ActiveJob::TestCase
  class ThrottledJob < ApplicationJob
    include RateLimited

    def perform
      raise RateLimit::Throttled.new(retry_after: 3)
    end
  end

  class HookJob < ApplicationJob
    include RateLimited

    cattr_accessor :exhausted_with

    def perform
      raise RateLimit::Throttled.new(retry_after: 3)
    end

    private

    def on_rate_limit_exhausted(error)
      self.class.exhausted_with = error
    end
  end

  test "reschedules the job when throttled within the attempt cap" do
    assert_enqueued_with(job: ThrottledJob) do
      ThrottledJob.perform_now
    end
  end

  test "gives up and reports RetriesExhausted once the attempt cap is reached" do
    job = ThrottledJob.new
    job.executions = RateLimited::MAX_ATTEMPTS

    reported = []
    Rails.error.stub(:report, ->(error, **) { reported << error }) do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_equal 1, reported.size
    assert_instance_of RateLimited::RetriesExhausted, reported.first
    assert_includes reported.first.message, "Rate limited"
  end

  test "invokes on_rate_limit_exhausted once the attempt cap is reached" do
    HookJob.exhausted_with = nil
    job = HookJob.new
    job.executions = RateLimited::MAX_ATTEMPTS

    Rails.error.stub(:report, ->(*, **) { }) do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_instance_of RateLimit::Throttled, HookJob.exhausted_with
  end
end
