require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  setup do
    ActionMailer::Base.default_url_options[:host] = "example.com"
  end

  test "should reset" do
    user = create(:user)
    message = nil

    assert_difference -> { Event.where(type: "mail.passwords_mailer.reset").count }, 1 do
      message = PasswordsMailer.reset(user).deliver_now
    end

    assert_equal "Reset your password", message.subject
    assert_equal [user.email_address], message.to
    assert_equal ["noreply@frf.im"], message.from
    assert_match "password reset", message.body.encoded.downcase

    event = Event.where(type: "mail.passwords_mailer.reset", user: user).order(:created_at).last

    assert_equal "info", event.level
    assert_equal user, event.subject
    assert_equal "passwords_mailer", event.metadata["mailer"]
    assert_equal "reset", event.metadata["action"]
    assert_equal({}, event.metadata["details"])
  end
end
