require "test_helper"

class ProfileMailerTest < ActionMailer::TestCase
  test "email_change_confirmation" do
    user = create(:user)
    new_email = "new_email#{user.id}@example.com"
    user.update!(unconfirmed_email: new_email)

    message = nil
    assert_difference -> { Event.where(type: "email_change_confirmation_requested").count }, 1 do
      message = ProfileMailer.email_change_confirmation(user).deliver_now
    end

    assert_equal "Confirm your new email address", message.subject
    assert_equal [new_email], message.to
    assert_equal ["noreply@frf.im"], message.from

    event = Event.where(type: "email_change_confirmation_requested", user: user).order(:created_at).last
    assert_equal user, event.user
    assert_equal user, event.subject
    assert_equal [new_email], event.metadata["recipient"]
  end

  test "account_confirmation" do
    user = create(:user)
    message = nil
    assert_difference -> { Event.where(type: "email_confirmation_requested").count }, 1 do
      message = ProfileMailer.account_confirmation(user).deliver_now
    end

    assert_equal "Confirm your email address", message.subject
    assert_equal [user.email_address], message.to
    assert_equal ["noreply@frf.im"], message.from

    event = Event.where(type: "email_confirmation_requested", user: user).order(:created_at).last
    assert_equal user, event.user
    assert_equal user, event.subject
    assert_equal [user.email_address], event.metadata["recipient"]
  end
end
