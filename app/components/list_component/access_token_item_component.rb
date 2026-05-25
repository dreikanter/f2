class ListComponent::AccessTokenItemComponent < ViewComponent::Base
  include ApplicationHelper
  include TimeHelper

  UNKNOWN_USER = "...".freeze

  def initialize(access_token:, key: nil)
    @access_token = access_token
    @key = key
  end

  private

  def username_with_host
    raise "AccessToken should be valid at this point" unless @access_token.valid?

    if @access_token.owner.present?
      "#{@access_token.owner}@#{@access_token.host_domain}"
    else
      "Host: #{@access_token.host_domain}"
    end
  end

  def created_ago
    short_time_ago(@access_token.created_at)
  end

  def last_used_text
    if @access_token.last_used_at
      short_time_ago(@access_token.last_used_at)
    else
      "Never"
    end
  end
end
