require "test_helper"

class AppConfigGateTest < ActiveSupport::TestCase
  # Without a decryption key every credential silently reads as nil. The boot
  # gate must turn that into a startup failure listing every violation.
  test "production refuses to boot without required credentials" do
    # The subprocess must not be able to decrypt real production credentials,
    # or the gate legitimately passes. A nil env value unsets the variable for
    # the child. The on-disk key can only be skipped around.
    key_file = Rails.root.join("config/credentials/production.key")
    skip "#{key_file} would decrypt real credentials" if key_file.exist?

    env = {
      "RAILS_ENV" => "production",
      "RAILS_MASTER_KEY" => nil,
      "SECRET_KEY_BASE" => "dummy",
      "HOSTS" => "example.com",
      "ACTION_MAILER_HOST" => "example.com",
      "MAILER_FROM" => "hello@example.com"
    }

    output = nil
    Dir.chdir(Rails.root) do
      output = IO.popen(env, ["bin/rails", "runner", "puts :booted"], err: [:child, :out], &:read)
    end

    assert_not $?.success?, "production booted without credentials: #{output}"
    assert_includes output, "resend_api_key: required in production but not set"
    assert_includes output, "resend_signing_secret: required in production but not set"
  end
end
