class AiCredentials::ModelCatalogsController < ApplicationController
  def create
    authorize credential, :update?
    credential.refresh_models_async(force: true)
    redirect_to ai_credential_path(credential)
  end

  def show
    authorize credential, :show?
    return head :no_content if credential.models_refreshing?

    render turbo_stream: turbo_stream.update(
      "ai-credential-model-catalog",
      partial: "ai_credentials/model_catalog_content",
      locals: { ai_credential: credential }
    )
  end

  private

  def credential
    @credential ||= Current.user.ai_credentials.find(params[:ai_credential_id])
  end
end
