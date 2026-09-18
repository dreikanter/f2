class AiCredentialsController < CredentialsController
  self.credential_class = AiCredential
  self.validation_job = AiCredentialValidationJob

  private

  def credential_params
    super.merge(params.require(:ai_credential).permit(:default_model))
  end

  def updated_credential_attrs(credential_updates:)
    super.merge(credential_params.slice(:default_model))
  end

  def default_provider
    LlmProvider.names.first
  end

  def credential_noun
    "AI credential"
  end
end
