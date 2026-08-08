class SearchCredentials::DefaultsController < CredentialDefaultsController
  self.credential_class = SearchCredential

  private

  def credential_noun
    "search credential"
  end
end
