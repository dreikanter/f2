require "json"
require "time"

module EmailStorage
  class FileSystemStorage < Base
    # Times are stored as ISO8601 strings; everything else is a plain JSON
    # scalar. JSON.parse can only produce basic types, so the writer and reader
    # are locked to the same format with no allow-list to keep in sync.
    TIME_KEYS = %w[timestamp date].freeze

    def initialize(base_dir = nil)
      @base_dir = base_dir || Rails.root.join("tmp", "sent_emails")
      validate_directory!
    end

    def list
      return [] unless Dir.exist?(base_dir)

      Dir.glob(base_dir.join("*.json")).map do |json_path|
        filename = File.basename(json_path, ".json")
        match = filename.match(/_([0-9a-f\-]+)$/)
        next unless match

        metadata = read_metadata(json_path)
        next unless metadata

        {
          id: match[1],
          subject: metadata["subject"],
          timestamp: parse_time(metadata["timestamp"]) || File.mtime(json_path),
          size: File.size(json_path)
        }
      end.compact
    end

    def load_email(uuid)
      filename = find_filename(uuid)
      return nil unless filename

      metadata = read_metadata(base_dir.join("#{filename}.json"))
      return nil unless metadata

      text_content = load_text_content(filename)
      html_content = load_html_content(filename)

      {
        message_id: metadata["message_id"],
        from: metadata["from"],
        to: metadata["to"],
        subject: metadata["subject"],
        date: parse_time(metadata["date"]),
        multipart: metadata["multipart"] || false,
        body: metadata["multipart"] ? "" : text_content,
        text_part: metadata["multipart"] ? text_content : nil,
        html_part: html_content
      }
    end

    def save_email(metadata:, text_content:, html_content: nil)
      FileUtils.mkdir_p(base_dir)

      uuid = new_id
      filename = filename_for(uuid, metadata["timestamp"])
      base_path = base_dir.join(filename)

      File.write("#{base_path}.json", JSON.generate(serialize(metadata)))
      File.write("#{base_path}.txt", text_content)
      File.write("#{base_path}.html", html_content) if html_content

      uuid
    end

    def email_exists?(uuid)
      find_filename(uuid).present?
    end

    # Wipes the whole directory, so any leftover files (including legacy YAML
    # captures) are removed regardless of format.
    def purge
      FileUtils.rm_rf(base_dir)
      FileUtils.mkdir_p(base_dir)
    end

    private

    attr_reader :base_dir

    def serialize(metadata)
      metadata.to_h do |key, value|
        [key, TIME_KEYS.include?(key) ? format_time(value) : value]
      end
    end

    def format_time(value)
      return value unless value.respond_to?(:iso8601)
      value.iso8601(3)
    rescue ArgumentError
      # Date#iso8601 takes no precision argument; fall back to its bare form.
      value.iso8601
    end

    def parse_time(value)
      return if value.blank?
      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def filename_for(uuid, timestamp)
      timestamp_str = timestamp.strftime("%Y%m%d_%H%M%S_%L")
      "#{timestamp_str}_#{uuid}"
    end

    def find_filename(uuid)
      return nil unless Dir.exist?(base_dir)

      matches = Dir.glob(base_dir.join("*_#{uuid}.json"))
      return nil if matches.empty?

      File.basename(matches.first, ".json")
    end

    def read_metadata(path)
      parsed = JSON.parse(File.read(path))
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError, Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email metadata from #{path}: #{e.message}"
      nil
    end

    def load_text_content(id)
      path = base_dir.join("#{id}.txt")
      File.exist?(path) ? File.read(path) : nil
    rescue Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email text from #{path}: #{e.message}"
      nil
    end

    def load_html_content(id)
      path = base_dir.join("#{id}.html")
      File.exist?(path) ? File.read(path) : nil
    rescue Errno::ENOENT, IOError => e
      Rails.logger.error "Failed to load email HTML from #{path}: #{e.message}"
      nil
    end

    def validate_directory!
      absolute_dir = base_dir.expand_path

      raise "Email directory path is blank" if absolute_dir.to_s.blank?

      allowed_base = Rails.root.join("tmp").expand_path
      unless absolute_dir.to_s.start_with?(allowed_base.to_s + "/")
        raise "Email directory must be inside #{allowed_base}"
      end

      @base_dir = absolute_dir
    end
  end
end
