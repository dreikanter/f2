# Event model for tracking email delivery delays from Resend webhooks
class EmailDelayedEvent
  # Creates an email delayed event
  # @param user [User, nil] the user if found
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailDelayedEvent",
      level: :warning,
      subject: user,
      user: user,
      message: user ? "Email delivery delayed for #{user.email_address}" : "Email delivery delayed",
      metadata: data
    )
  end
end
