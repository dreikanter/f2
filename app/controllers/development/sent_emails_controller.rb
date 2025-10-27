class Development::SentEmailsController < ApplicationController
  allow_unauthenticated_access

  def index
    @emails = email_storage.list_emails.sort_by { |e| e[:timestamp] }.reverse
  end

  def show
    unless params[:id] =~ /\A\d{8}_\d{6}_\d{3}_[0-9a-f-]{36}\z/
      redirect_to development_sent_emails_path, alert: "Invalid email ID"
      return
    end

    unless email_storage.email_exists?(params[:id])
      redirect_to development_sent_emails_path, alert: "Email not found"
      return
    end

    @email = email_storage.load_email(params[:id])

    unless @email
      redirect_to development_sent_emails_path, alert: "Failed to load email"
      return
    end
  end

  def purge
    email_storage.purge_all
    redirect_to development_sent_emails_path, notice: "All emails purged"
  rescue => e
    redirect_to development_sent_emails_path, alert: "Failed to purge emails: #{e.message}"
  end

  private

  def email_storage
    @email_storage ||= EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter)
  end
end
