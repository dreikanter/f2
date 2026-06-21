module EmailStorage
  class Base
    def list
      raise NotImplementedError
    end

    def ordered_list
      # Fall back to the epoch so emails with a missing timestamp (legacy or
      # malformed files) sort last instead of raising on a nil comparison.
      list.sort_by { |e| e[:timestamp] || Time.at(0) }.reverse
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
  end
end
