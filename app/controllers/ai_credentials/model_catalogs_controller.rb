class AiCredentials::ModelCatalogsController < ApplicationController
  include StatePolling

  def create
    authorize credential, :update?
    credential.refresh_models_async(force: true)
    redirect_to ai_credential_path(credential, feed_id: params[:feed_id])
  end

  def show
    authorize credential, :show?
    return head :no_content if credential.models_refreshing?

    render turbo_stream: turbo_stream.update(
      "ai-credential-show",
      partial: "ai_credentials/show_content",
      locals: { ai_credential: credential, feed_id: params[:feed_id] }
    )
  end

  private

  def credential
    @credential ||= Current.user.ai_credentials.find(params[:ai_credential_id])
  end
end
