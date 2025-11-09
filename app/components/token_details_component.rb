class TokenDetailsComponent < ViewComponent::Base
  def initialize(access_token:)
    @access_token = access_token
  end

  private

  def freefeed_user
    @access_token.owner.presence || "–"
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
