class AiCredentialsController < CredentialsController
  self.credential_class = AiCredential
  self.validation_job = AiCredentialValidationJob

  def show
    super
    @credential.refresh_models_async
  end

  private

  def default_provider
    LlmProvider.names.first
  end

  def credential_noun
    "AI credential"
  end
end
