class TokenValidationJob < ApplicationJob
  queue_as :default

  def perform(access_token)
    return unless access_token.token_value.present?

    begin
      user_info = freefeed_client(access_token).whoami
      access_token.update!(status: :active, owner: user_info[:username])
    rescue FreefeedClient::UnauthorizedError
      access_token.inactive!
    rescue => e
      access_token.inactive!
    end
  end

  private

  def freefeed_client(access_token)
    FreefeedClient.new(host: access_token.host, token: access_token.token_value)
  end
end
