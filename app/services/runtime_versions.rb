class RuntimeVersions
  def initialize(os_release_path: "/etc/os-release")
    @os_release_path = os_release_path
  end

  def call
    {
      ruby: RUBY_VERSION,
      bundler: Bundler::VERSION,
      rails: Rails.version,
      operating_system: operating_system,
      postgresql: ApplicationRecord.connection.select_value("SHOW server_version")
    }
  end

  private

  def operating_system
    return "Unknown" unless File.readable?(@os_release_path)

    line = File.foreach(@os_release_path).find { |entry| entry.start_with?("PRETTY_NAME=") }
    value = line&.split("=", 2)&.last&.strip
    value = value&.sub(/\A(["'])(.*)\1\z/, '\2')

    value.presence || "Unknown"
  end
end
