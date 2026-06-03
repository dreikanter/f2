require_relative "production"

Rails.application.configure do
  # Staging mirrors production but keeps developer-only tools available for QA.
  config.x.dev_tools.enabled = true
  config.x.dev_tools.require_auth = true

  # Use filesystem storage for captured emails in staging (dev tools are enabled).
  config.email_storage_adapter = :file_system
end
