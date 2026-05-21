class ResendWebhookEvent
  def initialize(data)
    @data = data
  end

  def recipient_email
    to.first
  end

  def raw_data
    {
      email_id: @data[:email_id],
      from: @data[:from],
      to: to,
      subject: @data[:subject],
      created_at: @data[:created_at],
      broadcast_id: @data[:broadcast_id],
      tags: @data[:tags] || {},
      bounce: @data[:bounce],
      click: @data[:click],
      failed: @data[:failed]
    }.compact
  end

  private

  def to
    Array(@data[:to])
  end
end
