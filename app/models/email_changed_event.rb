# Event model for tracking email address changes
class EmailChangedEvent
  # Creates an email changed event
  # @param user [User] the user whose email was changed
  # @param old_email [String] the previous email address
  # @param new_email [String] the new email address
  # @return [Event] created event record
  def self.create(user:, old_email:, new_email:)
    Event.create!(
      type: "EmailChangedEvent",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from #{old_email} to #{new_email}",
      metadata: { old_email: old_email, new_email: new_email }
    )
  end
end
