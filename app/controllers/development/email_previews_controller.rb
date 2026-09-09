class Development::EmailPreviewsController < ApplicationController
  def index
    authorize [:development, :email_preview], :index?
    @previews = EmailPreview.all
  end

  def show
    authorize [:development, :email_preview], :show?
    @preview = EmailPreview.find(params[:id])
    return redirect_to(development_email_previews_path, alert: "Unknown email type.") unless @preview

    message = EmailPreview.delivery(@preview[:id]).message
    @subject = message.subject
    @html_body = message.html_part&.decoded
    @text_body = message.text_part&.decoded
  end
end
