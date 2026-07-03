require "test_helper"

class JobRunTest < ActiveSupport::TestCase
  test "#runnable_job should return the job class for a registered name" do
    assert_equal PurgeExpiredEventsJob, JobRun.runnable_job("PurgeExpiredEventsJob")
  end

  test "#runnable_job should return nil for an unregistered name" do
    assert_nil JobRun.runnable_job("SomeOtherJob")
  end

  test "#job_class should be required" do
    run = JobRun.new(job_class: nil)

    assert_not run.valid?
    assert_includes run.errors[:job_class], "can't be blank"
  end

  test "#status should default to queued" do
    assert_predicate JobRun.new, :queued?
  end
end
