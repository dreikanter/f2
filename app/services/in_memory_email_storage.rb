class InMemoryEmailStorage < EmailStorage
  def initialize
    @mutex = Mutex.new
    @emails = {}
  end

  def list_emails
    @mutex.synchronize do
      @emails.values.map do |email|
        filename = email[:id]
        match = filename.match(/^(\d{8}_\d{6}_\d{3})_([0-9a-f\-]+)$/)
        next unless match

        timestamp_str = match[1]
        timestamp = DateTime.strptime(timestamp_str, "%Y%m%d_%H%M%S_%L")

        {
          id: filename,
          subject: email[:metadata]["subject"],
          timestamp: timestamp,
          size: email[:metadata].to_yaml.bytesize
        }
      end.compact
    end
  end

  def load_email(id)
    @mutex.synchronize do
      email = @emails[id]
      return nil unless email

      metadata = email[:metadata]
      text_content = email[:text_content]
      html_content = email[:html_content]

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
  end

  def save_email(id, metadata:, text_content:, html_content: nil)
    @mutex.synchronize do
      @emails[id] = {
        id: id,
        metadata: metadata,
        text_content: text_content,
        html_content: html_content
      }
    end
  end

  def email_exists?(id)
    @mutex.synchronize do
      @emails.key?(id)
    end
  end

  def purge_all
    @mutex.synchronize do
      @emails.clear
    end
  end
end
