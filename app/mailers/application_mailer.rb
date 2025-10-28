class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@frf.im")
  layout "mailer"

  private

  def set_event_context(level: nil, user_id: nil, subject: nil, details: nil)
    @event_context = {
      level: level,
      user_id: user_id,
      subject: subject,
      details: details
    }
  end

  def register_event
    Event.create!(
      type: event_type,
      level: event_context[:level] || :info,
      user_id: event_context[:user_id],
      subject: event_context[:subject],
      metadata: {
        mailer: mailer_name,
        action: action_name,
        details: event_context[:details]&.as_json || {}
      }
    )
  end

  def event_context
    @event_context ||= {}
  end

  def event_type
    "mail.#{mailer_name}.#{action_name}"
  end
end
