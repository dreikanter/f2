class AiCredentials::DefaultsController < ApplicationController
  def update
    authorize credential, :update?

    credential.make_default!
    message = "'#{credential.display_name}' is now the default credential."
    redirect_to ai_credentials_path, success: message
  end

  private

  def credential
    @credential ||= scope.find(params[:ai_credential_id])
  end

  def scope
    policy_scope(AiCredential)
  end
end
