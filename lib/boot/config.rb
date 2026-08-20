require_relative "config_registry"

# Every credential or environment setting the app consumes is declared here
# exactly once and read only through this class (Config.resend_api_key,
# Config.imgproxy?).
#
# required and validate are independent: an optional setting that is set
# still gets validated, because misconfigured is not the same as missing.
# normalize canonicalizes a present value, so consumers never see raw quirks
# such as trailing slashes.
#
# The boot gate (config/initializers/config_gate.rb) runs Config.validate!
# after initialization, so a misconfigured process fails to start.
class Config < ConfigRegistry
  IMGPROXY_SETTINGS = %i[imgproxy_endpoint imgproxy_key imgproxy_salt].freeze

  setting :resend_api_key,
    source: -> { Rails.application.credentials.dig(:resend, :api_key) },
    required: -> { !Rails.env.local? },
    validate: NON_BLANK_TOKEN

  setting :resend_signing_secret,
    source: -> { Rails.application.credentials.dig(:resend, :signing_secret) },
    required: -> { !Rails.env.local? },
    validate: NON_BLANK_TOKEN

  setting :honeybadger_api_key,
    source: -> { Rails.application.credentials.dig(:honeybadger, :api_key) },
    validate: NON_BLANK_TOKEN

  setting :imgproxy_endpoint,
    source: -> { Rails.application.credentials.dig(:imgproxy, :endpoint) },
    normalize: ->(value) { value.sub(%r{/+\z}, "") },
    validate: HTTP_URL

  setting :imgproxy_key,
    source: -> { Rails.application.credentials.dig(:imgproxy, :key) },
    validate: HEX_BYTES

  setting :imgproxy_salt,
    source: -> { Rails.application.credentials.dig(:imgproxy, :salt) },
    validate: HEX_BYTES

  setting :metrics_url,
    source: -> { ENV["METRICS_URL"].presence },
    validate: HTTP_URL

  setting :metrics_username,
    source: -> { ENV["METRICS_USERNAME"].presence }

  setting :metrics_password,
    source: -> { ENV["METRICS_PASSWORD"].presence }

  setting :metrics_flush_interval,
    source: -> { ENV["METRICS_FLUSH_INTERVAL"].presence },
    default: "15",
    validate: POSITIVE_INTEGER

  setting :metrics_instance,
    source: -> { ENV["METRICS_INSTANCE"].presence }

  setting :app_revision,
    source: -> { ENV["APP_REVISION"].presence }

  setting :app_revision_short,
    source: -> { ENV["APP_REVISION_SHORT"].presence },
    default: -> { app_revision&.first(7) }

  setting :app_deployed_at,
    source: -> { ENV["APP_DEPLOYED_AT"].presence },
    validate: PARSEABLE_TIME

  def self.imgproxy?
    IMGPROXY_SETTINGS.all? { |name| public_send("#{name}?") }
  end

  # imgproxy is configured all-or-nothing: off when every setting is absent,
  # on when all are present, and anything in between fails the gate. A
  # complete, individually valid trio must also sign a sample URL. Signing
  # is a local HMAC, so this proves the values compose through the real
  # ImgproxyUrl pipeline without touching the network.
  check :imgproxy do
    present = IMGPROXY_SETTINGS.select { |name| public_send("#{name}?") }
    missing = IMGPROXY_SETTINGS - present

    if present.none?
      []
    elsif missing.any?
      ["imgproxy: partial configuration (missing: #{missing.join(", ")}). Set all of #{IMGPROXY_SETTINGS.join(", ")} or none"]
    elsif IMGPROXY_SETTINGS.any? { |name| setting_violations(settings.fetch(name)).any? }
      []
    else
      sample = ImgproxyUrl.preview("https://example.com/sample.jpg")
      sample.start_with?("#{imgproxy_endpoint}/") ? [] : ["imgproxy: signing a sample URL failed"]
    end
  end
end
