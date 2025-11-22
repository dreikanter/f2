class AccessTokens::GroupsController < ApplicationController
  GROUPS_CACHE_TTL = 10.minutes

  def index
    render turbo_stream: turbo_stream.replace(
      "target-group-selector",
      partial: "feeds/target_group_selector",
      locals: locals.merge(feed: feed, token: access_token)
    )
  end

  private

  def locals
    if access_token.blank?
      error_locals(:missing_token)
    elsif access_token.active?
      Rails.cache.delete(cache_key) if bust_cache?
      groups = Rails.cache.fetch(cache_key, expires_in: GROUPS_CACHE_TTL) { fetch_groups_from_freefeed }

      {
        groups: groups,
        token_error: groups.empty? ? :empty : nil
      }
    else
      error_locals(:inactive_token)
    end
  rescue FreefeedClient::UnauthorizedError => e
    error_locals(:unauthorized)
  rescue StandardError => e
    error_locals(:api_error)
  end

  def error_locals(error)
    {
      groups: [],
      token_error: error
    }
  end

  def access_token
    if defined?(@access_token)
      @access_token
    else
      @access_token ||= current_user.access_tokens.find_by(id: params[:access_token_id])
    end
  end

  def feed
    @feed ||= current_user.feeds.find_by(id: params[:feed_id]) || current_user.feeds.build
  end

  def cache_key
    "access_token_groups/#{access_token.id}"
  end

  def bust_cache?
    params[:retry].present?
  end

  def fetch_groups_from_freefeed
    access_token.build_client.managed_groups.map { |group| group[:username] }
  end
end
