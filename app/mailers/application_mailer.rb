class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@frf.im")
  layout "mailer"

  private

  def record_transactional_email_event(action:, user:, message:)
    TransactionalEmailEventRecorder.record_for(
      mailer: self.class.name,
      action: action,
      user: user,
      message: message
    )
  end
end
