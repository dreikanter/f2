# Event model for tracking email opens from Resend webhooks
class EmailOpenedEvent
  # Creates an email opened event
  # @param user [User, nil] the user if found
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailOpenedEvent",
      level: :info,
      subject: user,
      user: user,
      message: user ? "Email opened by #{user.email_address}" : "Email opened",
      metadata: data
    )
  end
end
