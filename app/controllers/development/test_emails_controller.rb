class Development::TestEmailsController < ApplicationController
  def create
    authorize [:development, :email_preview], :create?
    preview = EmailPreview.find(params[:email_preview_id])
    redirect_to(development_email_previews_path, alert: "Unknown email type.") and return unless preview

    EmailPreviewTestJob.perform_later(preview[:id], current_user.email_address)
    redirect_to development_email_preview_path(preview[:id]),
                success: "Test email sent to #{current_user.email_address}."
  end
end
