class SearchCredentialsController < CredentialsController
  self.credential_class = SearchCredential
  self.validation_job = SearchCredentialValidationJob

  private

  def default_provider
    WebSearchProvider::REGISTRY.keys.first
  end

  def credential_noun
    "Search credential"
  end
end
