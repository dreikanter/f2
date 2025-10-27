module EmailStorage
  class Base
    def list_emails
      raise NotImplementedError
    end

    def load_email(id)
      raise NotImplementedError
    end

    def save_email(metadata:, text_content:, html_content: nil)
      raise NotImplementedError
    end

    def email_exists?(id)
      raise NotImplementedError
    end

    def purge
      raise NotImplementedError
    end

    protected

    def new_id
      SecureRandom.uuid
    end

    def ordered_list(emails)
      emails.sort_by { |e| e[:timestamp] }.reverse
    end
  end
end
