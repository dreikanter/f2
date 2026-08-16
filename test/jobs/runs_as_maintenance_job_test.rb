require "test_helper"

class RunsAsMaintenanceJobTest < ActiveSupport::TestCase
  test "#display_name should read the class name as prose without the Job suffix" do
    assert_equal "Anthropic Capability Probe", AnthropicCapabilityProbeJob.display_name
    assert_equal "Purge Expired Events", PurgeExpiredEventsJob.display_name
  end

  test "every runnable job should be a maintenance job" do
    JobRun::RUNNABLE_JOBS.each do |klass|
      assert klass.include?(RunsAsMaintenanceJob),
             "#{klass} is listed in RUNNABLE_JOBS but does not include RunsAsMaintenanceJob"
    end
  end
end
