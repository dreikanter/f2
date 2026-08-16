require "test_helper"

class ApplicationJobTest < ActiveSupport::TestCase
  test "#display_name should read the class name as prose without the Job suffix" do
    assert_equal "Anthropic Capability Probe", AnthropicCapabilityProbeJob.display_name
    assert_equal "Purge Expired Events", PurgeExpiredEventsJob.display_name
  end
end
