class SearchCredentials::DefaultsController < CredentialDefaultsController
  before_action { head :not_found unless Rails.configuration.x.external_search_enabled }

  self.credential_class = SearchCredential

  private

  def credential_noun
    "search credential"
  end
end
