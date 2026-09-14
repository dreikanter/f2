class AiCredentials::ModelCatalogsController < ApplicationController
  include StatePolling

  def create
    authorize credential, :update?
    RefreshLlmModelsJob.perform_later
    redirect_to ai_credential_path(credential, feed_id: params[:feed_id])
  end

  def show
    authorize credential, :show?
    return head :no_content if helpers.llm_models_refreshing?

    render turbo_stream: turbo_stream.replace(
      "ai-credential-model-catalog",
      partial: "ai_credentials/model_catalog",
      locals: { ai_credential: credential, feed_id: params[:feed_id] }
    )
  end

  private

  def credential
    @credential ||= Current.user.ai_credentials.find(params[:ai_credential_id])
  end
end
