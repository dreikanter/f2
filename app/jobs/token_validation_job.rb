class TokenValidationJob < ApplicationJob
  queue_as :default

  def perform(access_token)
    AccessTokenValidationService.new(access_token).call
  end
end
