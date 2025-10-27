require "test_helper"

class ProfileMailerTest < ActionMailer::TestCase
  test "email_change_confirmation" do
    user = create(:user)
    new_email = "new_email#{user.id}@example.com"
    user.update!(unconfirmed_email: new_email)

    mail = ProfileMailer.email_change_confirmation(user)
    assert_equal "Confirm your new email address", mail.subject
    assert_equal [new_email], mail.to
    assert_equal ["noreply@frf.im"], mail.from

    assert_difference -> { Event.where(type: "email_change_confirmation_requested").count }, 1 do
      mail.deliver_now
    end

    event = Event.where(type: "email_change_confirmation_requested", user: user).order(:created_at).last
    assert_equal user, event.user
    assert_equal user, event.subject
    assert_equal [new_email], event.metadata["recipient"]
  end

  test "account_confirmation" do
    user = create(:user)
    mail = ProfileMailer.account_confirmation(user)
    assert_equal "Confirm your email address", mail.subject
    assert_equal [user.email_address], mail.to
    assert_equal ["noreply@frf.im"], mail.from

    assert_difference -> { Event.where(type: "email_confirmation_requested").count }, 1 do
      mail.deliver_now
    end

    event = Event.where(type: "email_confirmation_requested", user: user).order(:created_at).last
    assert_equal user, event.user
    assert_equal user, event.subject
    assert_equal [user.email_address], event.metadata["recipient"]
  end
end
