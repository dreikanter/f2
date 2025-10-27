class TransactionalEmailEventRecorder
  SUPPORTED_MAILERS = %w[ProfileMailer PasswordsMailer].freeze
  CONTEXT_IVAR = :@_transactional_email_context

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

  def self.attach_context(message:, mailer:, action:, user:)
    return unless supports?(mailer: mailer, action: action)

    message.instance_variable_set(
      CONTEXT_IVAR,
      {
        mailer: mailer.to_s,
        action: action.to_sym,
        user: user
      }
    )
  end

  def self.record_from_message(message)
    context = message.instance_variable_get(CONTEXT_IVAR)
    return unless context

    message.instance_variable_set(CONTEXT_IVAR, nil)

    record!(
      mailer: context[:mailer],
      action: context[:action],
      user: context[:user],
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

  class Observer
    def delivered_email(message)
      TransactionalEmailEventRecorder.record_from_message(message)
    end
  end
end
