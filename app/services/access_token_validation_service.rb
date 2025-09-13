class AccessTokenValidationService
  def initialize(access_token)
    @access_token = access_token
  end

  def call
    return unless @access_token.token_value.present?

    ActiveRecord::Base.transaction do
      begin
        user_info = freefeed_client.whoami
        @access_token.update!(status: :active, owner: user_info[:username])
      rescue FreefeedClient::UnauthorizedError
        update_token_and_disable_feeds(:inactive)
      rescue => e
        update_token_and_disable_feeds(:inactive)
      end
    end
  end

  private

  def freefeed_client
    FreefeedClient.new(host: @access_token.host, token: @access_token.token_value)
  end

  def update_token_and_disable_feeds(status)
    @access_token.update!(status: status)

    if status == :inactive
      @access_token.feeds.enabled.update_all(state: :disabled)
    end
  end
end
