class AiCredentials::ValidationsController < ApplicationController
  def show
    ai_credential = scope.find(params[:ai_credential_id])
    authorize ai_credential, :show?, policy_class: AiCredentialPolicy

    # Stay silent while validation is still in flight so the poller leaves the
    # spinner running instead of redrawing (and restarting) it every cycle.
    return head :no_content if ai_credential.pending? || ai_credential.validating?

    render turbo_stream: turbo_stream.update(
      "ai-credential-show",
      partial: "ai_credentials/show_content",
      locals: { ai_credential: ai_credential, feed_id: params[:feed_id] }
    )
  end

  private

  def scope
    policy_scope(AiCredential)
  end
end
