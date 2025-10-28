module EmailStorage
  class FileSystemStorage < Base
    def initialize(base_dir = nil)
      @base_dir = base_dir || Rails.root.join("tmp", "sent_emails")
      validate_directory!
    end

    def list
      return [] unless Dir.exist?(base_dir)

      Dir.glob(base_dir.join("*.yml")).map do |yml_path|
        filename = File.basename(yml_path, ".yml")
        match = filename.match(/_([0-9a-f\-]+)$/)
        next unless match

        uuid = match[1]

        begin
          metadata = YAML.safe_load_file(yml_path, permitted_classes: [Time, Date, DateTime], aliases: true) || {}
        rescue Psych::SyntaxError
          next
        end

        {
          id: uuid,
          subject: metadata["subject"],
          timestamp: metadata["timestamp"],
          size: File.size(yml_path)
        }
      end.compact
    end

    def load_email(uuid)
      filename = find_filename(uuid)
      return nil unless filename

      metadata = load_metadata(filename)
      return nil unless metadata

      text_content = load_text_content(filename)
      html_content = load_html_content(filename)

      {
        message_id: metadata["message_id"],
        from: metadata["from"],
        to: metadata["to"],
        subject: metadata["subject"],
        date: metadata["date"],
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

      File.write("#{base_path}.yml", metadata.to_yaml)
      File.write("#{base_path}.txt", text_content)
      File.write("#{base_path}.html", html_content) if html_content

      uuid
    end

    def email_exists?(uuid)
      find_filename(uuid).present?
    end

    def purge
      FileUtils.rm_rf(base_dir)
      FileUtils.mkdir_p(base_dir)
    end

    private

    attr_reader :base_dir

    def filename_for(uuid, timestamp)
      timestamp_str = timestamp.strftime("%Y%m%d_%H%M%S_%L")
      "#{timestamp_str}_#{uuid}"
    end

    def find_filename(uuid)
      return nil unless Dir.exist?(base_dir)

      pattern = base_dir.join("*_#{uuid}.yml")
      matches = Dir.glob(pattern)
      return nil if matches.empty?

      File.basename(matches.first, ".yml")
    end

    def load_metadata(id)
      path = base_dir.join("#{id}.yml")
      return unless File.exist?(path)
      YAML.safe_load_file(path, permitted_classes: [Time, Date, DateTime], aliases: true) || {}
    rescue Psych::SyntaxError, Errno::ENOENT, IOError => e
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
