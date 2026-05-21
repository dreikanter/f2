class LlmCredentials::DefaultsController < ApplicationController
  def update
    credential = scope.find(params[:llm_credential_id])
    authorize credential, :update?

    credential.make_default!

    provider_name = LlmProvider.find(credential.provider)&.display_name
    redirect_to llm_credentials_path, notice: "'#{credential.display_name}' is now the default for #{provider_name}."
  end

  private

  def scope
    policy_scope(LlmCredential)
  end
end
