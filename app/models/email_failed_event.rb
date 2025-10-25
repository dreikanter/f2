# Event model for tracking email delivery failures from Resend webhooks
class EmailFailedEvent
  # Creates an email failed event
  # @param user [User] the user whose email failed
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailFailedEvent",
      level: :error,
      subject: user,
      user: user,
      message: "Email delivery failed for #{user.email_address}",
      metadata: data
    )
  end
end
