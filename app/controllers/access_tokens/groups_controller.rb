class AccessTokens::GroupsController < ApplicationController
  GROUPS_CACHE_TTL = 10.minutes

  def index
    Rails.cache.delete(cache_key) if bust_cache?

    render turbo_stream: turbo_stream.replace(
      "target-group-selector",
      partial: "feeds/target_group_selector",
      locals: locals.merge(feed: feed, token: access_token)
    )
  end

  private

  def locals
    if access_token.active?
      groups = Rails.cache.fetch(cache_key, expires_in: GROUPS_CACHE_TTL) do
        fetch_groups_from_freefeed(access_token)
      end

      {
        groups: groups,
        token_error: groups.empty? ? :empty : nil
      }
    else
      {
        groups: [],
        token_error: :inactive_token
      }
    end
  rescue FreefeedClient::UnauthorizedError => e
    {
      groups: [],
      token_error: :unauthorized
    }
  rescue StandardError => e
    {
      groups: [],
      token_error: :api_error
    }
  end

  def fetch_groups_with_cache
  end

  def access_token
    @access_token ||= current_user.access_tokens.find_by(id: params[:access_token_id])
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

  def fetch_groups_from_freefeed(token)
    token.build_client.managed_groups.map { |group| group[:username] }
  end
end
