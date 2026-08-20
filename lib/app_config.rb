require "uri"

# Registry for external configuration. Every credential or environment
# setting the app consumes is declared here exactly once and read only through
# this class (AppConfig.resend_api_key, AppConfig.imgproxy?).
#
# Each setting resolves as source, then default, then normalize, then
# validate. required and validate are independent: an optional setting that is
# set still gets validated, because misconfigured is not the same as missing.
# normalize canonicalizes a present value, so consumers never see raw quirks
# such as trailing slashes.
#
# .validate! evaluates every declaration and raises one error listing every
# violation. The boot gate (config/initializers/app_config.rb) runs it after
# initialization, so a misconfigured process fails to start. Checks are local
# only. Violation messages never include setting values.
class AppConfig
  class ConfigurationError < StandardError; end

  Setting = Data.define(:name, :source, :required, :default, :normalize, :validate)

  IMGPROXY_SETTINGS = %i[imgproxy_endpoint imgproxy_key imgproxy_salt].freeze

  class << self
    def validate!
      violations = settings.each_value.flat_map { |setting| setting_violations(setting) }
      violations += imgproxy_violations
      return if violations.none?

      raise ConfigurationError, "Invalid application configuration:\n#{violations.map { |text| "- #{text}" }.join("\n")}"
    end

    def imgproxy?
      IMGPROXY_SETTINGS.all? { |name| public_send("#{name}?") }
    end

    # Effective configuration for the system status page. Booleans only,
    # never values: most settings are secrets.
    def status
      settings.keys.index_with { |name| public_send("#{name}?") }
    end

    private

    def settings
      @settings ||= {}
    end

    def setting(name, source:, required: false, default: nil, normalize: nil, validate: nil)
      settings[name] = Setting.new(name:, source:, required:, default:, normalize:, validate:)

      define_singleton_method(name) { value_of(name) }
      define_singleton_method("#{name}?") { public_send(name).present? }
    end

    def value_of(name)
      setting = settings.fetch(name)
      value = setting.source.call
      value = resolve(setting.default) if value.blank?
      value = setting.normalize.call(value) if setting.normalize && value.present?
      value
    end

    def resolve(value)
      value.respond_to?(:call) ? value.call : value
    end

    def setting_violations(setting)
      value = value_of(setting.name)

      if value.blank?
        return resolve(setting.required) ? ["#{setting.name}: required in #{Rails.env} but not set"] : []
      end

      return [] if setting.validate.nil? || setting.validate.call(value)

      ["#{setting.name}: present but invalid"]
    rescue StandardError => e
      ["#{setting.name}: evaluation raised #{e.class}"]
    end

    # imgproxy is configured all-or-nothing: off when every setting is absent,
    # on when all are present, and anything in between fails the gate. A
    # complete, individually valid trio must also sign a sample URL. Signing
    # is a local HMAC, so this proves the values compose through the real
    # ImgproxyUrl pipeline without touching the network.
    def imgproxy_violations
      # Throwaway test registries declare their own settings only.
      return [] unless IMGPROXY_SETTINGS.all? { |name| settings.key?(name) }

      present = IMGPROXY_SETTINGS.select { |name| public_send("#{name}?") }
      return [] if present.none?

      missing = IMGPROXY_SETTINGS - present
      if missing.any?
        return ["imgproxy: partial configuration (missing: #{missing.join(", ")}). Set all of #{IMGPROXY_SETTINGS.join(", ")} or none"]
      end

      return [] if IMGPROXY_SETTINGS.any? { |name| setting_violations(settings.fetch(name)).any? }

      sample = ImgproxyUrl.preview("https://example.com/sample.jpg")
      sample.start_with?("#{imgproxy_endpoint}/") ? [] : ["imgproxy: signing a sample URL failed"]
    rescue StandardError => e
      ["imgproxy: evaluation raised #{e.class}"]
    end
  end

  HTTP_URL = lambda do |value|
    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Decodable by Array#pack("H*"): hex digits forming whole bytes.
  HEX_BYTES = ->(value) { value.match?(/\A\h+\z/) && value.length.even? }

  NON_BLANK_TOKEN = ->(value) { value.match?(/\A\S+\z/) }

  POSITIVE_INTEGER = ->(value) { value.match?(/\A[1-9]\d*\z/) }

  PARSEABLE_TIME = lambda do |value|
    Time.zone.parse(value).present?
  rescue ArgumentError
    false
  end

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
end
