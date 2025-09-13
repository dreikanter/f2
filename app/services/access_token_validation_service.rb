class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    ActiveRecord::Base.transaction do
      begin
        user_info = freefeed_client.whoami
        access_token.update!(status: :active, owner: user_info[:username])
      rescue
        disable_token_and_feeds
      end
    end
  end

  private

  def freefeed_client
    FreefeedClient.new(
      host: access_token.host,
      token: access_token.token_value
    )
  end

  def disable_token_and_feeds
    access_token.update!(status: :inactive)
    access_token.feeds.enabled.update_all(state: :disabled)
  end
end
