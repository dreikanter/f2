class Development::EmailPreviewsController < ApplicationController
  def index
    authorize [:development, :email_preview], :index?
    @previews = EmailPreview.all
  end

  def show
    authorize [:development, :email_preview], :show?
    @preview = EmailPreview.find(params[:id])
    redirect_to(development_email_previews_path, alert: "Unknown email type.") and return unless @preview

    message = build_message
    @subject = message.subject
    @html_body = message.html_part&.decoded
    @text_body = message.text_part&.decoded
  end

  private

  def build_message
    ApplicationMailer.preview_mode = true
    EmailPreview.delivery(@preview[:id]).message
  ensure
    ApplicationMailer.preview_mode = false
  end
end
