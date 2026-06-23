class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@frf.im")
  layout "mailer"

  def self.preview_mode=(value)
    Thread.current[:mailer_preview_mode] = value
  end

  def self.preview_mode?
    Thread.current[:mailer_preview_mode]
  end

  def self.sample_mode=(value)
    Thread.current[:mailer_sample_mode] = value
  end

  # Messages built from sample data — email previews and the test emails sent
  # from them — must not register Events, since their sample recipient has no
  # real user record. Previews additionally suppress delivery (preview_mode);
  # test sends keep the real backend so the message is actually delivered.
  def self.sample_mode?
    Thread.current[:mailer_sample_mode] || preview_mode?
  end

  # Building a message instantiates the configured delivery backend, and the
  # Resend backend raises when no API key is set. Previews only render the
  # message and never deliver it, so swap in the no-op :test backend.
  def wrap_delivery_behavior!(*)
    return super unless self.class.preview_mode?

    super(:test)
  end

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
    return if self.class.sample_mode?

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
