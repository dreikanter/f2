require "test_helper"

class EmailStorageAdapterConfigTest < ActiveSupport::TestCase
  # Reading config.email_storage_adapter used to raise NoMethodError on staging,
  # which inherits production and never set the attribute. Defining the default
  # in application.rb fixes it, but the test environment overrides the value, so
  # the regression only shows when an environment provides no override. Boot the
  # production environment in a subprocess to assert the attribute is defined.
  test "email_storage_adapter is defined without an environment override" do
    # A marker isolates our value from any gem warnings printed to stdout.
    script = 'puts "ADAPTER:#{Rails.application.config.email_storage_adapter}"'
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "dummy",
      "HOSTS" => "example.com",
      "ACTION_MAILER_HOST" => "example.com"
    }

    output = nil
    Dir.chdir(Rails.root) do
      output = IO.popen(env, ["bin/rails", "runner", script], err: File::NULL, &:read)
    end

    assert $?.success?, "production environment failed to boot"
    assert_includes output, "ADAPTER:file_system"
  end
end
