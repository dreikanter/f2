require_relative "production"

Rails.application.configure do
  # Staging mirrors production but keeps developer-only tools available for QA.
  config.x.dev_tools.enabled = true
end
