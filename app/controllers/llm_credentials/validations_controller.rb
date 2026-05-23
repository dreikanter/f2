class LlmCredentials::ValidationsController < ApplicationController
  def show
    llm_credential = scope.find(params[:llm_credential_id])
    authorize llm_credential, :show?, policy_class: LlmCredentialPolicy

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
