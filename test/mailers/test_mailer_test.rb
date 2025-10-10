require "test_helper"

class TestMailerTest < ActionMailer::TestCase
  test "ping" do
    email_address = "test@example.com"
    mail = TestMailer.ping(email_address)

    assert_equal "Test email from Feeder", mail.subject
    assert_equal [email_address], mail.to
    assert_equal ["noreply@frf.im"], mail.from
  end

  test "ping with different email address" do
    email_address = "another@example.com"
    mail = TestMailer.ping(email_address)

    assert_equal [email_address], mail.to
  end

  test "ping has text and html parts" do
    mail = TestMailer.ping("test@example.com")

    assert mail.multipart?
    assert_not_nil mail.text_part
    assert_not_nil mail.html_part
    assert_includes mail.text_part.body.to_s, "This is a test email from Feeder"
    assert_includes mail.html_part.body.to_s, "This is a test email from Feeder"
  end
end
