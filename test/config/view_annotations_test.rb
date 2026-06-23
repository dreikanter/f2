require "test_helper"

class ViewAnnotationsConfigTest < ActiveSupport::TestCase
  # Staging enables ViewComponent/partial source-file annotations to ease
  # debugging, while production keeps them off. The setting is applied at boot,
  # so each environment is booted in a subprocess to read the resolved value.
  # A marker isolates our value from any gem warnings printed to stdout.
  SCRIPT = 'puts "ANNOTATE:#{Rails.application.config.action_view.annotate_rendered_view_with_filenames.inspect}"'.freeze

  test "annotations are enabled on staging" do
    assert_includes boot("staging"), "ANNOTATE:true"
  end

  test "annotations stay off on production" do
    refute_includes boot("production"), "ANNOTATE:true"
  end

  private

  def boot(environment)
    env = {
      "RAILS_ENV" => environment,
      "SECRET_KEY_BASE" => "dummy",
      "HOSTS" => "example.com",
      "ACTION_MAILER_HOST" => "example.com"
    }

    output = nil
    Dir.chdir(Rails.root) do
      output = IO.popen(env, ["bin/rails", "runner", SCRIPT], err: File::NULL, &:read)
    end

    assert $?.success?, "#{environment} environment failed to boot"
    output
  end
end
