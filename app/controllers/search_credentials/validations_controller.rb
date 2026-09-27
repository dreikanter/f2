class SearchCredentials::ValidationsController < ValidationsController
  before_action { head :not_found unless Features.external_search? }

  self.validated_class = SearchCredential
end
