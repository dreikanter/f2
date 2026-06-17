class AiCredentials::DefaultsController < ApplicationController
  def update
    authorize credential, :update?

    credential.make_default!
    message = "'#{credential.display_name}' is now the default for #{provider_name}."
    redirect_to ai_credentials_path, success: message
  end

  private

  def provider_name
    @provider_name ||= LlmProvider.find(credential.provider).display_name
  end

  def credential
    @credential ||= scope.find(params[:ai_credential_id])
  end

  def scope
    policy_scope(AiCredential)
  end
end
