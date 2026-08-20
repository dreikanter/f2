# Declaration machinery for the Config registry (lib/config.rb). Extended
# into the registry class: `setting` declares one external value and defines
# its reader and presence predicate; each value resolves as source, then
# default, then normalize, then validate.
module ConfigDsl
  Setting = Data.define(:name, :source, :required, :default, :normalize, :validate)

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
    raise ArgumentError, "duplicate setting: #{name}" if settings.key?(name)

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

  def settings_violations
    settings.each_value.flat_map { |setting| setting_violations(setting) }
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
end
