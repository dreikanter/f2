class TokenDetailsComponent < ViewComponent::Base
  def initialize(access_token:)
    @access_token = access_token
  end

  private

  def freefeed_user
    return "–" unless @access_token.active?
    return "–" unless @access_token.access_token_detail && !@access_token.access_token_detail.expired?

    details = @access_token.access_token_detail.data
    user_info = details["user_info"]
    user_info["username"]
  end

  def freefeed_instance
    URI.parse(@access_token.host).host
  end

  def last_used
    return "–" if @access_token.inactive?

    @access_token.last_used_at ? helpers.datetime_with_duration_tag(@access_token.last_used_at) : "Never"
  end

  def created
    helpers.datetime_with_duration_tag(@access_token.created_at)
  end
end
