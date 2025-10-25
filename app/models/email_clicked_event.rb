# Event model for tracking email link clicks from Resend webhooks
class EmailClickedEvent
  # Creates an email clicked event
  # @param user [User, nil] the user if found
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailClickedEvent",
      level: :info,
      subject: user,
      user: user,
      message: user ? "Email link clicked by #{user.email_address}" : "Email link clicked",
      metadata: data
    )
  end
end
