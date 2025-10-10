class FileDelivery
  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    dir = Rails.root.join("tmp", "sent_emails")
    FileUtils.mkdir_p(dir)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S_%L")
    filename = "#{timestamp}_#{sanitize_filename(mail.subject || "no_subject")}.txt"
    filepath = dir.join(filename)

    File.open(filepath, "w") do |f|
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
