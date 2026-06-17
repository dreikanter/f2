class AiCredentials::DefaultsController < ApplicationController
  def update
    authorize credential, :update?

    credential.make_default!

    respond_to do |format|
      format.turbo_stream do
        flash.now[:success] = "'#{credential.display_name}' is now the default credential."
        @ai_credentials = policy_scope(AiCredential).order(created_at: :desc)
      end
      format.html do
        redirect_to ai_credentials_path, success: "'#{credential.display_name}' is now the default credential."
      end
    end
  end

  private

  def credential
    @credential ||= scope.find(params[:ai_credential_id])
  end

  def scope
    policy_scope(AiCredential)
  end
end
