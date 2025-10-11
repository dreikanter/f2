# Usage: TestMailer.ping("email@example.com").deliver_now
class TestMailer < ApplicationMailer
  def ping(email_address)
    mail subject: "Test email from Feeder", to: email_address
  end
end
