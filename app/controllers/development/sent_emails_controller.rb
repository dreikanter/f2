class Development::SentEmailsController < ApplicationController
  def index
    authorize :access, :dev?
    @emails = email_storage.ordered_list
  end

  def show
    authorize :access, :dev?
    id = params[:id]

    return redirect_to development_sent_emails_path, alert: "Invalid email ID" unless id.match?(/\A[0-9a-f-]{36}\z/)
    return redirect_to development_sent_emails_path, alert: "Email not found" unless email_storage.email_exists?(id)

    @email = email_storage.load_email(id)

    unless @email
      redirect_to development_sent_emails_path, alert: "Failed to load email"
    end
  end

  private

  def email_storage
    @email_storage ||= EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter)
  end
end
