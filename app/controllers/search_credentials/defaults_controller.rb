class SearchCredentials::DefaultsController < CredentialDefaultsController
  before_action { head :not_found unless Features.external_search? }

  self.credential_class = SearchCredential

  private

  def credential_noun
    "search credential"
  end
end
