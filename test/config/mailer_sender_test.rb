require "test_helper"

class MailerSenderConfigTest < ActiveSupport::TestCase
  # ApplicationMailer used to default the sender to an address on a domain that
  # was never verified in Resend, so a deploy missing MAILER_FROM looked healthy
  # and failed one delivery at a time. Production now has no fallback; boot it in
  # a subprocess to prove a missing sender stops the app instead.
  test "production refuses to boot without MAILER_FROM" do
    output, status = boot_production("MAILER_FROM" => nil)

    assert_not status.success?, "production booted without a sender: #{output}"
    assert_includes output, "MAILER_FROM"
  end

  test "production uses MAILER_FROM as the sender" do
    output, status = boot_production("MAILER_FROM" => "hello@example.com")

    assert status.success?, "production environment failed to boot"
    assert_includes output, "FROM:hello@example.com"
  end

  private

  # A marker isolates our value from any gem warnings printed to stdout.
  SCRIPT = 'puts "FROM:#{ApplicationMailer.default_params[:from]}"'.freeze

  def boot_production(overrides)
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "dummy",
      "HOSTS" => "example.com",
      "ACTION_MAILER_HOST" => "example.com"
    }.merge(overrides)

    output = nil
    Dir.chdir(Rails.root) do
      output = IO.popen(env, ["bin/rails", "runner", SCRIPT], err: [:child, :out], &:read)
    end

    [output, $?]
  end
end
