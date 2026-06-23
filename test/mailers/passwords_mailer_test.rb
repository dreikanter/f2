require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  setup do
    ActionMailer::Base.default_url_options[:host] = "example.com"
  end

  test "#reset should build a password reset email" do
    user = create(:user)
    message = PasswordsMailer.reset(user)

    assert_equal "Reset your password", message.subject
    assert_equal [user.email_address], message.to
    assert_equal ["noreply@frf.im"], message.from
    assert_match "password reset", message.body.encoded.downcase
  end
end
