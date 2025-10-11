require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  setup do
    ActionMailer::Base.default_url_options[:host] = "example.com"
  end

  test "reset" do
    user = create(:user)
    mail = PasswordsMailer.reset(user)

    assert_equal "Reset your password", mail.subject
    assert_equal [user.email_address], mail.to
    assert_equal ["noreply@frf.im"], mail.from
    assert_match "password reset", mail.body.encoded.downcase
  end
end
