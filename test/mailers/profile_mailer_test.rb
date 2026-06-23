require "test_helper"

class ProfileMailerTest < ActionMailer::TestCase
  test "#email_change_confirmation should build a confirmation email to the new address" do
    user = create(:user)
    new_email = "new_email#{user.id}@example.com"
    user.update!(unconfirmed_email: new_email)

    message = ProfileMailer.email_change_confirmation(user)

    assert_equal "Confirm your new email address", message.subject
    assert_equal [new_email], message.to
    assert_equal ["noreply@frf.im"], message.from
  end

  test "#account_confirmation should build a confirmation email to the user" do
    user = create(:user)
    message = ProfileMailer.account_confirmation(user)

    assert_equal "Confirm your email address", message.subject
    assert_equal [user.email_address], message.to
    assert_equal ["noreply@frf.im"], message.from
  end
end
