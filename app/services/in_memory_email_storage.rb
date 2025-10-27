class InMemoryEmailStorage < EmailStorage
  def initialize
    @mutex = Mutex.new
    @emails = {}
  end

  def list_emails
    @mutex.synchronize do
      @emails.values.map do |email|
        full_id = email[:full_id]
        match = full_id.match(/^(\d{8}_\d{6}_\d{3})_([0-9a-f\-]+)$/)
        next unless match

        timestamp_str = match[1]
        uuid = match[2]
        timestamp = DateTime.strptime(timestamp_str, "%Y%m%d_%H%M%S_%L")

        {
          id: uuid,
          subject: email[:metadata]["subject"],
          timestamp: timestamp,
          size: email[:metadata].to_yaml.bytesize
        }
      end.compact
    end
  end

  def load_email(uuid)
    @mutex.synchronize do
      full_id = find_full_id(uuid)
      return nil unless full_id

      email = @emails[full_id]
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

  def save_email(full_id, metadata:, text_content:, html_content: nil)
    @mutex.synchronize do
      @emails[full_id] = {
        full_id: full_id,
        metadata: metadata,
        text_content: text_content,
        html_content: html_content
      }
    end
  end

  def email_exists?(uuid)
    @mutex.synchronize do
      find_full_id(uuid).present?
    end
  end

  def purge_all
    @mutex.synchronize do
      @emails.clear
    end
  end

  private

  def find_full_id(uuid)
    @emails.keys.find { |key| key.end_with?("_#{uuid}") }
  end
end
