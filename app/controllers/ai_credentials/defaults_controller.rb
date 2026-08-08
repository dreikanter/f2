class AiCredentials::DefaultsController < CredentialDefaultsController
  self.credential_class = AiCredential

  private

  def credential_noun
    "credential"
  end
end
