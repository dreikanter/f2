class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  # Queue a message to a user and record it in their log in one step, so the
  # event always names the action that was actually sent.
  # @param action [Symbol] the mailer action to deliver
  # @param user [User] the recipient the message and the event belong to
  # @return [Event] the recorded delivery
  def self.deliver_to(action, user)
    public_send(action, user).deliver_later
    Event.create!(type: event_type(action), user: user, subject: user, level: :info)
  end

  # @param action [Symbol] the mailer action
  # @return [String] the event type naming that message
  def self.event_type(action)
    "mail.#{name.underscore}.#{action}"
  end
end
