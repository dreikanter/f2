class SearchCredentialsController < CredentialsController
  before_action { head :not_found unless Features.external_search? }

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
