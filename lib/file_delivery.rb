class FileDelivery
  def initialize(settings)
    @settings = settings
    @email_storage = settings[:email_storage]
  end

  def deliver!(mail)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S_%L")
    uuid = SecureRandom.uuid
    id = "#{timestamp}_#{uuid}"

    metadata = {
      "message_id" => mail.message_id.to_s,
      "from" => mail.from&.join(", "),
      "to" => mail.to&.join(", "),
      "subject" => mail.subject.to_s,
      "date" => mail.date,
      "multipart" => mail.multipart?
    }

    text_content = mail.multipart? ? mail.text_part&.body&.decoded : mail.body.decoded
    html_content = mail.multipart? ? mail.html_part&.body&.decoded : nil

    email_storage.save_email(
      id,
      metadata: metadata,
      text_content: text_content || "",
      html_content: html_content
    )

    Rails.logger.info "Email saved with ID: #{id}"
  end

  private

  def email_storage
    @email_storage ||= EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter)
  end
end
