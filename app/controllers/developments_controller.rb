class DevelopmentsController < ApplicationController
  def show
    authorize :access, :dev?
    # Only the :file delivery method captures messages into the local store the
    # Sent Emails page reads from. Other methods (e.g. :resend) actually send the
    # mail, leaving nothing to browse, so the link stays disabled.
    @sent_emails_available = ActionMailer::Base.delivery_method == :file
  end
end
