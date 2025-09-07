# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Configure Action Mailer for testing
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "example.com" }

  # Use test adapter for jobs - runs jobs inline during tests
  config.active_job.queue_adapter = :test

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Active Record encryption configuration for tests
  config.active_record.encryption.primary_key = "Iy3CIs4hElWox2ylk1vxB2L0vzMtmBIR"
  config.active_record.encryption.deterministic_key = "KztQVQFifzXvAVzYZRpYhb4IpbB3LbsN"
  config.active_record.encryption.key_derivation_salt = "VsCuex5mmS3GP4Qu28NpLFEw99NgMVM5"
end

# Set test environment specific variables
ENV["FREEFEED_HOST"] = "https://freefeed.test"
