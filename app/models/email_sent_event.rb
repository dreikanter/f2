# Event model for tracking emails sent via Resend
class EmailSentEvent
  # Creates an email sent event
  # @param user [User, nil] the user if found
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailSentEvent",
      level: :info,
      subject: user,
      user: user,
      message: user ? "Email sent to #{user.email_address}" : "Email sent",
      metadata: data
    )
  end
end
