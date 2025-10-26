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
    filename = "#{timestamp}_#{uuid}.txt"
    filepath = dir.join(filename)

    write_file.call(filepath) do |f|
      # Write YAML frontmatter
      frontmatter = {
        "message_id" => mail.message_id.to_s,
        "from" => mail.from&.join(", "),
        "to" => mail.to&.join(", "),
        "subject" => mail.subject.to_s,
        "date" => mail.date,
        "multipart" => mail.multipart?
      }
      f.puts frontmatter.to_yaml
      f.puts "---"
      f.puts ""

      # Write body
      if mail.multipart?
        f.puts "TEXT:"
        f.puts mail.text_part&.body&.decoded || "(no text part)"
        f.puts ""
        f.puts "HTML:"
        f.puts mail.html_part&.body&.decoded || "(no html part)"
      else
        f.puts mail.body.decoded
      end
    end

    Rails.logger.info "Email saved to #{filepath}"
  end
end
