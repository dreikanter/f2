class FileDelivery
  attr_reader :mkdir_p, :write_file

  def initialize(settings)
    @settings = settings
    @mkdir_p = settings[:mkdir_p] || ->(dir) { FileUtils.mkdir_p(dir) }
    @write_file = settings[:write_file] || ->(path, &block) { File.open(path, "w", &block) }
  end

  def deliver!(mail)
    dir = Rails.root.join("tmp", "sent_emails")
    mkdir_p.call(dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S_%L")
    uuid = SecureRandom.uuid
    base_name = "#{timestamp}_#{uuid}"

    # Write metadata file
    metadata = {
      "message_id" => mail.message_id.to_s,
      "from" => mail.from&.join(", "),
      "to" => mail.to&.join(", "),
      "subject" => mail.subject.to_s,
      "date" => mail.date,
      "multipart" => mail.multipart?
    }
    write_file.call(dir.join("#{base_name}.yml")) { |f| f.write(metadata.to_yaml) }

    # Write text version
    text_content = mail.multipart? ? mail.text_part&.body&.decoded : mail.body.decoded
    write_file.call(dir.join("#{base_name}.txt")) { |f| f.write(text_content || "") }

    # Write HTML version if multipart
    if mail.multipart?
      html_content = mail.html_part&.body&.decoded
      write_file.call(dir.join("#{base_name}.html")) { |f| f.write(html_content || "") }
    end

    Rails.logger.info "Email saved to #{dir.join(base_name)}.*"
  end
end
