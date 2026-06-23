class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@frf.im")
  layout "mailer"

  def self.preview_mode=(value)
    Thread.current[:mailer_preview_mode] = value
  end

  def self.preview_mode?
    Thread.current[:mailer_preview_mode]
  end

  # Building a message instantiates the configured delivery backend, and the
  # Resend backend raises when no API key is set. Previews only render the
  # message and never deliver it, so swap in the no-op :test backend.
  def wrap_delivery_behavior!(*)
    return super unless self.class.preview_mode?

    super(:test)
  end
end
