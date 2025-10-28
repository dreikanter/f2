module EmailStorage
  class Base
    def list
      raise NotImplementedError
    end

    def ordered_list
      list.sort_by { |e| e[:timestamp] }.reverse
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
