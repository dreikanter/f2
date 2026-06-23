# Catalog of mailer messages rendered with sample data for the dev-only email
# previews. The same sample messages can be delivered on demand as test emails
# so devs can see how a template looks in a real inbox.
class EmailPreview
  CATALOG = [
    {
      id: "passwords_mailer-reset",
      label: "Password Reset",
      description: "Sent when someone requests a password reset"
    },
    {
      id: "profile_mailer-account_confirmation",
      label: "Account Confirmation",
      description: "Sent during signup to verify the email address"
    },
    {
      id: "profile_mailer-email_change_confirmation",
      label: "Email Change Confirmation",
      description: "Sent when a user requests an email address change"
    },
    {
      id: "test_mailer-ping",
      label: "Test Ping",
      description: "A minimal test email to verify delivery is working"
    }
  ].freeze

  def self.all
    CATALOG
  end

  def self.find(id)
    CATALOG.find { _1[:id] == id }
  end

  # A MessageDelivery built from sample data, or nil for an unknown id.
  def self.delivery(id)
    return unless find(id)

    user = sample_user

    case id
    when "passwords_mailer-reset"
      PasswordsMailer.reset(user)
    when "profile_mailer-account_confirmation"
      ProfileMailer.account_confirmation(user)
    when "profile_mailer-email_change_confirmation"
      ProfileMailer.email_change_confirmation(user)
    when "test_mailer-ping"
      TestMailer.ping(user.email_address)
    end
  end

  def self.sample_user
    user = User.new(
      email_address: "preview@example.com",
      name: "Sam Preview",
      password: "previewpassword",
      unconfirmed_email: "new.preview@example.com"
    )
    user.id = 0
    user
  end
end
