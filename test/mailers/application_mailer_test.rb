require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  def user
    @user ||= create(:user)
  end

  test ".deliver_to should queue the message to the user" do
    assert_enqueued_emails 1 do
      PasswordsMailer.deliver_to(:reset, user)
    end
  end

  test ".deliver_to should record the delivery against the user" do
    event = ProfileMailer.deliver_to(:account_confirmation, user)

    assert_equal "mail.profile_mailer.account_confirmation", event.type
    assert_equal user, event.user
    assert_equal user, event.subject
    assert_predicate event, :info?
  end

  test ".event_type should name the mailer action" do
    assert_equal "mail.passwords_mailer.reset", PasswordsMailer.event_type(:reset)
  end
end
