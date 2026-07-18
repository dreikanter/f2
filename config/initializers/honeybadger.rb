Honeybadger.configure do |config|
  config.api_key = Rails.application.credentials.dig(:honeybadger, :api_key)
  config.env = Rails.env
  config.root = Rails.root.to_s
  # Tie reported errors to the deployed git revision. Kamal injects
  # APP_REVISION at deploy time (see config/deploy.yml).
  config.revision = ENV.fetch("APP_REVISION", nil)
  config.development_environments = %w[test development]
  config.insights.enabled = true
  # Honeybadger checks ActiveRecord too early when loading this plugin.
  # TODO: Remove after honeybadger-ruby#812 lands and ships: https://github.com/honeybadger-io/honeybadger-ruby/pull/812
  config.solid_queue.insights.enabled = false
  config.exceptions.ignore += [SignalException]

  # The webhook capability token rides in the request path; keep it out of
  # error reports the same way it's kept out of access logs (spec 006 §6).
  config.before_notify do |notice|
    notice.url = WebhookLogScrubbing.scrub(notice.url.to_s) if notice.url
    notice.cgi_data&.transform_values! { |value| value.is_a?(String) ? WebhookLogScrubbing.scrub(value) : value }
  end
end
