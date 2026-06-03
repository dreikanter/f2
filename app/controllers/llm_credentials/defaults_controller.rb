class LlmCredentials::DefaultsController < ApplicationController
  def update
    authorize credential, :update?

    credential.make_default!
    message = "'#{credential.display_name}' is now the default for #{provider_name}."
    redirect_to llm_credentials_path, notice: message
  end

  private

  def provider_name
    @provider_name ||= LlmProvider.find(credential.provider).display_name
  end

  def credential
    @credential ||= scope.find(params[:llm_credential_id])
  end

  def scope
    policy_scope(LlmCredential)
  end
end
