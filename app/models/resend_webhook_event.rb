class ResendWebhookEvent
  def initialize(data)
    @data = data
  end

  def email_id
    @email_id ||= @data[:email_id]
  end

  def from
    @from ||= @data[:from]
  end

  def to
    @to ||= Array(@data[:to])
  end

  def subject
    @subject ||= @data[:subject]
  end

  def created_at
    @created_at ||= @data[:created_at]
  end

  def broadcast_id
    @broadcast_id ||= @data[:broadcast_id]
  end

  def tags
    @tags ||= @data[:tags] || {}
  end

  def bounce
    @bounce ||= @data[:bounce]
  end

  def click
    @click ||= @data[:click]
  end

  def failed
    @failed ||= @data[:failed]
  end

  def recipient_email
    to.first
  end

  def raw_data
    {
      email_id: email_id,
      from: from,
      to: to,
      subject: subject,
      created_at: created_at,
      broadcast_id: broadcast_id,
      tags: tags,
      bounce: bounce,
      click: click,
      failed: failed
    }.compact
  end
end
