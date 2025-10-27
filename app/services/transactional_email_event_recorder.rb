class TransactionalEmailEventRecorder
  SUPPORTED_MAILERS = %w[ProfileMailer PasswordsMailer].freeze

  EMAIL_EVENT_DEFINITIONS = {
    account_confirmation: {
      type: "email_confirmation_requested",
      message: "Sent account confirmation email"
    },
    email_change_confirmation: {
      type: "email_change_confirmation_requested",
      message: "Sent email change confirmation"
    },
    reset: {
      type: "password_reset_requested",
      message: "Sent password reset email"
    }
  }.freeze

  def self.record_for(mailer:, action:, user:, message:)
    return unless supports?(mailer: mailer, action: action)
    return if message.blank?

    record!(
      mailer: mailer,
      action: action,
      user: user,
      recipient: message.to
    )
  end

  def self.record!(mailer:, action:, user:, recipient:)
    return unless user&.persisted?

    definition = EMAIL_EVENT_DEFINITIONS.fetch(action.to_sym)

    Event.create!(
      type: definition.fetch(:type),
      level: :info,
      user: user,
      subject: user,
      message: definition.fetch(:message),
      metadata: {
        mailer: mailer,
        action: action.to_s,
        recipient: Array(recipient)
      }
    )
  end

  def self.supports?(mailer:, action:)
    mailer.present? &&
      action.present? &&
      SUPPORTED_MAILERS.include?(mailer.to_s) &&
      EMAIL_EVENT_DEFINITIONS.key?(action.to_sym)
  end
end
