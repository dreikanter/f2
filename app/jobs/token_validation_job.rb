class TokenValidationJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(access_token)
    # Validation makes two GETs: whoami and managedGroups.
    RateLimit.acquire!(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 2 })

    AccessTokenValidationService.new(access_token).call
  end
end
