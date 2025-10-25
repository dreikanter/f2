# Event model for tracking email bounces from Resend webhooks
class EmailBouncedEvent
  # Creates an email bounced event
  # @param user [User] the user whose email bounced
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailBouncedEvent",
      level: :warning,
      subject: user,
      user: user,
      message: "Email bounced for #{user.email_address}",
      metadata: data
    )
  end
end
