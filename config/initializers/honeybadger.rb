Honeybadger.configure do |config|
  config.api_key = Rails.application.credentials.dig(:honeybadger, :api_key)
  config.env = Rails.env
  config.root = Rails.root.to_s
  config.development_environments = %w[test development]
  config.insights.enabled = true
  # Honeybadger checks ActiveRecord too early when loading this plugin.
  # TODO: Remove after honeybadger-ruby#812 lands and ships: https://github.com/honeybadger-io/honeybadger-ruby/pull/812
  config.solid_queue.insights.enabled = false
  config.exceptions.ignore += [SignalException]
  # Expected backpressure, not a fault: RateLimited reschedules throttled jobs,
  # but Honeybadger's around_perform callback sees the exception before
  # rescue_from runs and would report every reschedule. Throttle visibility
  # comes from the rate_limit.* events and metrics instead, and RateLimited
  # reports RetriesExhausted when it gives up for real. (String form: app
  # classes can't be autoloaded from an initializer.)
  config.exceptions.ignore += ["RateLimit::Throttled"]
end
