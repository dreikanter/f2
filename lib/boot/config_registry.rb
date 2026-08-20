require "uri"

# Base class for the Config registry (lib/boot/config.rb). `setting` declares
# one external value and defines its reader and presence predicate; each value
# resolves as source, then default, then normalize, then validate. `check`
# registers a named boot check that runs after per-setting validation.
#
# .validate! evaluates every declaration and raises one error listing every
# violation. Checks are local only. Violation messages never include setting
# values.
class ConfigRegistry
  class ConfigurationError < StandardError; end

  Setting = Data.define(:name, :source, :required, :default, :normalize, :validate)

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

  class << self
    def validate!
      violations = settings.each_value.flat_map { |setting| setting_violations(setting) }
      violations += checks.flat_map { |name, block| check_violations(name, block) }
      return if violations.none?

      raise ConfigurationError, "Invalid application configuration:\n#{violations.map { |text| "- #{text}" }.join("\n")}"
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

    def checks
      @checks ||= {}
    end

    def setting(name, source:, required: false, default: nil, normalize: nil, validate: nil)
      raise ArgumentError, "duplicate setting: #{name}" if settings.key?(name)

      settings[name] = Setting.new(name:, source:, required:, default:, normalize:, validate:)

      define_singleton_method(name) { value_of(name) }
      define_singleton_method("#{name}?") { public_send(name).present? }
    end

    # The block returns violation messages; raising is reported as a
    # violation too.
    def check(name, &block)
      raise ArgumentError, "duplicate check: #{name}" if checks.key?(name)

      checks[name] = block
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

    def check_violations(name, block)
      Array(block.call)
    rescue StandardError => e
      ["#{name}: evaluation raised #{e.class}"]
    end
  end
end
