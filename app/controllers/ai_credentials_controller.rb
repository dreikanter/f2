class AiCredentialsController < CredentialsController
  self.credential_class = AiCredential
  self.validation_job = AiCredentialValidationJob

  private

  def default_provider
    LlmProvider.names.first
  end

  def credential_noun
    "AI credential"
  end
end
