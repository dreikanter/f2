# Boot gate: refuse to start with missing or malformed external configuration.
# Every violation is reported at once, and a bad deploy never comes up
# half-working — Kamal's /up healthcheck fails and the deploy rolls back.
# Checks are local only; nothing here touches the network.
#
# SECRET_KEY_BASE_DUMMY marks the assets:precompile boot during the image
# build, which has no runtime configuration by design (see
# config/environments/production.rb). APP_CONFIG_GATE=skip is a seam for
# subprocess boot tests that exercise production config without production
# secrets (see test/config/).
Rails.application.config.after_initialize do
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next if ENV["APP_CONFIG_GATE"] == "skip"

  AppConfig.validate!
end
