class AiCredentialsController < CredentialsController
  self.credential_class = AiCredential
  self.validation_job = AiCredentialValidationJob

  private

  def default_provider
    LlmProvider.all.find(&:discovery_available?).name
  end

  def credential_noun
    "AI credential"
  end
end
