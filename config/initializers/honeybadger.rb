Honeybadger.configure do |config|
  config.api_key = Rails.application.credentials.dig(:honeybadger, :api_key)
  config.env = Rails.env
  config.root = Rails.root.to_s
  config.development_environments = %w[test development]
  config.exceptions.ignore += [SignalException]
end
