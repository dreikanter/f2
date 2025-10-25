require "test_helper"

class ProfileMailerTest < ActionMailer::TestCase
  test "email_change_confirmation" do
    mail = ProfileMailer.email_change_confirmation(build(:user), "new_email@example.com")
    assert_equal "Confirm your new email address", mail.subject
    assert_equal ["new_email@example.com"], mail.to
    assert_equal ["noreply@frf.im"], mail.from
  end

  test "account_confirmation" do
    user = build(:user, email_address: "user@example.com")
    mail = ProfileMailer.account_confirmation(user)
    assert_equal "Confirm your email address", mail.subject
    assert_equal ["user@example.com"], mail.to
    assert_equal ["noreply@frf.im"], mail.from
  end
end
