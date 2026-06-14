class LlmCredentials::ValidationsController < ApplicationController
  include StatePolling

  def show
    llm_credential = scope.find(params[:llm_credential_id])
    authorize llm_credential, :show?, policy_class: LlmCredentialPolicy

    return head :no_content if keep_polling?(llm_credential)

    render turbo_stream: turbo_stream.update(
      "llm-credential-show",
      partial: "llm_credentials/show_content",
      locals: { llm_credential: llm_credential, feed_id: params[:feed_id] }
    )
  end

  private

  def scope
    policy_scope(LlmCredential)
  end
end
