class SearchCredentials::ValidationsController < ValidationsController
  before_action { head :not_found unless Rails.configuration.x.external_search_enabled }

  self.validated_class = SearchCredential
end
