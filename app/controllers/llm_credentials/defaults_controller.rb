class LlmCredentials::DefaultsController < ApplicationController
  def update
    credential = scope.find(params[:llm_credential_id])
    authorize credential, :update?

    credential.make_default!

    redirect_to llm_credentials_path, notice: "'#{credential.display_name}' is now the default for #{LlmProvider.display_name_for(credential.provider)}."
  end

  private

  def scope
    policy_scope(LlmCredential)
  end
end
