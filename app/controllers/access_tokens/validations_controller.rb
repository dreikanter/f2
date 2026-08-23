class AccessTokens::ValidationsController < ValidationsController
  self.validated_class = AccessToken

  private

  def settle_abandoned_validation(access_token)
    AccessTokenValidationWatchdog.new(access_token).call
  end
end
