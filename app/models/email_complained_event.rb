# Event model for tracking email spam complaints from Resend webhooks
class EmailComplainedEvent
  # Creates an email complained event
  # @param user [User] the user who marked email as spam
  # @param data [Hash] webhook data from Resend
  # @return [Event] created event record
  def self.create(user:, data:)
    Event.create!(
      type: "EmailComplainedEvent",
      level: :warning,
      subject: user,
      user: user,
      message: "Email marked as spam for #{user.email_address}",
      metadata: data
    )
  end
end
