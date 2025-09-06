require "test_helper"

class ProfileMailerTest < ActionMailer::TestCase
  test "email_change_confirmation" do
    mail = ProfileMailer.email_change_confirmation(build(:user), "new_email@example.com")
    assert_equal "Confirm your new email address", mail.subject
    assert_equal ["new_email@example.com"], mail.to
    assert_equal ["from@example.com"], mail.from
  end
end
