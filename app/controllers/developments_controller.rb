class DevelopmentsController < ApplicationController
  def show
    authorize :access, :dev?
    @sent_emails_available = ActionMailer::Base.delivery_method == :file ||
      (ActionMailer::Base.delivery_method == :resend && Resend.api_key.present?)
  end
end
