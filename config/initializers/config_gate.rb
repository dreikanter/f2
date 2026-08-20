# Boot gate: refuse to start with missing or malformed external configuration.
# Every violation is reported at once. A bad deploy fails its /up healthcheck
# and Kamal rolls it back. Checks are local only.
#
# SECRET_KEY_BASE_DUMMY marks the assets:precompile boot during the image
# build, which has no runtime configuration by design (see
# config/environments/production.rb). CONFIG_GATE=skip is a seam for
# subprocess boot tests that exercise production config without production
# secrets (see test/config/).
Rails.application.config.after_initialize do
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?
  next if ENV["CONFIG_GATE"] == "skip"

  Config.validate!
end
