# Event model for tracking email deliveries from Resend webhooks
class EmailDeliveredEvent
  # Creates an email delivered event
  # @param user [User, nil] the user if found
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailDeliveredEvent",
      level: :info,
      subject: user,
      user: user,
      message: user ? "Email delivered to #{user.email_address}" : "Email delivered",
      metadata: data
    )
  end
end
