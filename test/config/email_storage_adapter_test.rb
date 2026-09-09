require "test_helper"

class EmailStorageAdapterConfigTest < ActiveSupport::TestCase
  # Staging inherits production and never sets config.email_storage_adapter, so
  # the default must live in application.rb. The test environment overrides the
  # value, so the check only holds when an environment provides no override.
  # Boot the production environment in a subprocess to assert the attribute is
  # defined.
  test "email_storage_adapter is defined without an environment override" do
    # A marker isolates our value from any gem warnings printed to stdout.
    script = 'puts "ADAPTER:#{Rails.application.config.email_storage_adapter}"'
    # The configuration gate needs production credentials this suite doesn't
    # have. Config.validate! is covered directly in config_test.rb.
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "dummy",
      "HOSTS" => "example.com",
      "ACTION_MAILER_HOST" => "example.com",
      "MAILER_FROM" => "noreply@example.com",
      "CONFIG_GATE" => "skip"
    }

    output = nil
    Dir.chdir(Rails.root) do
      output = IO.popen(env, ["bin/rails", "runner", script], err: File::NULL, &:read)
    end

    assert $?.success?, "production environment failed to boot"
    assert_includes output, "ADAPTER:file_system"
  end
end
