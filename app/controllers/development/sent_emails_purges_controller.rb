# Clearing the mailbox empties the whole collection, so it hangs off the
# collection rather than any one stored message.
class Development::SentEmailsPurgesController < ApplicationController
  def destroy
    authorize :access, :dev?
    EmailStorageResolver.resolve(Rails.application.config.email_storage_adapter).purge
    redirect_to development_sent_emails_path, success: "All emails purged"
  rescue => e
    redirect_to development_sent_emails_path, alert: "Failed to purge emails: #{e.message}"
  end
end
