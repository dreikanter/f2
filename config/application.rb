require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

require "set"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Initializers consume Config before the autoloader is ready, so lib/boot is
# required explicitly and excluded from zeitwerk (see autoload_lib below).
# Loading here predates SimpleCov, so lib/boot is also excluded from coverage
# (see test/test_helper.rb).
require_relative "../lib/boot/config"

# RubyLLM reads this when ActiveRecord loads, which happens before
# config/initializers run — hence the placement here. It opts into the
# association-based acts_as API that replaces the legacy one in RubyLLM 2.0.
# This app talks to the SDK directly and has no acts_as models, so the flag
# only silences the legacy deprecation warning.
RubyLLM.configure do |config|
  config.use_new_acts_as = true
end

module F2Rails
  GITHUB_REPO_URL = "https://github.com/dreikanter/f2".freeze

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks boot])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Default new models to UUIDv7 primary keys. UUIDv7 is time-ordered, so
    # inserts stay at the right edge of the index like a bigint sequence, and
    # ids are opaque and non-enumerable in URLs.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Configure ActiveJob to use SolidQueue
    config.active_job.queue_adapter = :solid_queue

    # Defined here so the attribute exists in every environment (staging and
    # production read it too); environments may override it.
    config.email_storage_adapter = :file_system
  end
end
