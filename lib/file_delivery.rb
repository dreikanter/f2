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
    filename = "#{timestamp}_#{sanitize_filename(mail.subject || "no_subject")}.txt"
    filepath = dir.join(filename)

    write_file.call(filepath) do |f|
      f.puts "From: #{mail.from&.join(", ")}"
      f.puts "To: #{mail.to&.join(", ")}"
      f.puts "Subject: #{mail.subject}"
      f.puts "Date: #{mail.date}"
      f.puts ""

      if mail.multipart?
        f.puts "--- TEXT PART ---"
        f.puts mail.text_part&.body&.decoded || "(no text part)"
        f.puts ""
        f.puts "--- HTML PART ---"
        f.puts mail.html_part&.body&.decoded || "(no html part)"
      else
        f.puts mail.body.decoded
      end
    end

    Rails.logger.info "Email saved to #{filepath}"
  end

  private

  def sanitize_filename(filename)
    filename.gsub(/[^0-9A-Za-z.\-]/, "_").slice(0, 50)
  end
end
