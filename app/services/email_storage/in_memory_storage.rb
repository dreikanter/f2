module EmailStorage
  class InMemoryStorage < Base
    def initialize
      @mutex = Mutex.new
      @emails = {}
    end

    def list_emails
      emails = @mutex.synchronize do
        @emails.values.map do |email|
          {
            id: email[:id],
            subject: email[:metadata]["subject"],
            timestamp: email[:metadata]["timestamp"],
            size: email[:metadata].to_yaml.bytesize
          }
        end
      end

      ordered_list(emails)
    end

    def load_email(uuid)
      @mutex.synchronize do
        email = @emails[uuid]
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

    def save_email(metadata:, text_content:, html_content: nil)
      uuid = new_id
      @mutex.synchronize do
        @emails[uuid] = {
          id: uuid,
          metadata: metadata,
          text_content: text_content,
          html_content: html_content
        }
      end
      uuid
    end

    def email_exists?(uuid)
      @mutex.synchronize do
        @emails.key?(uuid)
      end
    end

    def purge
      @mutex.synchronize do
        @emails.clear
      end
    end
  end
end
