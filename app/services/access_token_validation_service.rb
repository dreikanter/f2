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
        update_token_and_disable_feeds
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

  def update_token_and_disable_feeds
    access_token.update!(status: :inactive)
    access_token.feeds.enabled.update_all(state: :disabled)
  end
end
