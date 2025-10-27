class EmailStorage
  def list_emails
    raise NotImplementedError
  end

  def load_email(id)
    raise NotImplementedError
  end

  def save_email(id, metadata:, text_content:, html_content: nil)
    raise NotImplementedError
  end

  def email_exists?(id)
    raise NotImplementedError
  end

  def purge
    raise NotImplementedError
  end
end
