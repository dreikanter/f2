# Everything the activity log counts as mail: the messages this app sends, and
# the delivery reports Resend sends back about them.
module MailEvent
  # Resend's webhook types, and what each one means for the recipient. A
  # `handle_failure` report also takes the address out of service.
  DELIVERY_REPORTS = {
    "email.bounced" => {
      action: :handle_failure,
      level: :warning,
      reason: "bounced",
      type: "resend.email.email_bounced",
      message: "Email bounced"
    },
    "email.complained" => {
      action: :handle_failure,
      level: :warning,
      reason: "complained",
      type: "resend.email.email_complained",
      message: "Spam complaint"
    },
    "email.failed" => {
      action: :handle_failure,
      level: :error,
      reason: "failed",
      type: "resend.email.email_failed",
      message: "Email failed"
    },
    "email.sent" => {
      action: :track_only,
      level: :info,
      type: "resend.email.email_sent",
      message: "Email sent"
    },
    "email.delivered" => {
      action: :track_only,
      level: :info,
      type: "resend.email.email_delivered",
      message: "Email delivered"
    },
    "email.delivery_delayed" => {
      action: :track_only,
      level: :info,
      type: "resend.email.email_delayed",
      message: "Email delivery delayed"
    },
    "email.opened" => {
      action: :track_only,
      level: :info,
      type: "resend.email.email_opened",
      message: "Email opened"
    },
    "email.clicked" => {
      action: :track_only,
      level: :info,
      type: "resend.email.email_clicked",
      message: "Email clicked"
    }
  }.freeze

  # Events recorded when a message is queued.
  SENT = %w[
    mail.profile_mailer.account_confirmation
    mail.profile_mailer.email_change_confirmation
    mail.passwords_mailer.reset
  ].freeze

  # @return [Array<String>] every event type the mail filter selects
  def self.types
    DELIVERY_REPORTS.values.pluck(:type) + SENT
  end
end
