class AccessTokens::GroupsController < ApplicationController
  def index
    @token = Current.user.access_tokens.find_by(id: params[:access_token_id])
    @feed = Current.user.feeds.find_by(id: params[:feed_id]) || Current.user.feeds.build

    # Use find_by instead of find - if token not found or doesn't belong to user,
    # gracefully render empty selector (better UX for Turbo Stream context)
    @groups = if @token&.active?
      fetch_groups_with_cache(@token)
    else
      []
    end

    render turbo_stream: turbo_stream.replace(
      "target-group-selector",
      partial: "feeds/target_group_selector",
      locals: { feed: @feed, groups: @groups, token: @token }
    )
  end

  private

  def fetch_groups_with_cache(token)
    Rails.cache.fetch(
      "access_token_groups/#{token.id}",
      expires_in: 10.minutes,
      race_condition_ttl: 5.seconds,
      error_handler: ->(exception:, key:, **) {
        Rails.logger.error("Cache error for key #{key}: #{exception.message}")
      }
    ) do
      fetch_groups_from_freefeed(token)
    end
  rescue => e
    # FreeFeed API error - log and return empty array
    # Do not write to cache here - let Rails.cache.fetch handle race conditions
    Rails.logger.error("Failed to fetch groups for token #{token.id}: #{e.message}")
    []
  end

  def fetch_groups_from_freefeed(token)
    client = token.build_client
    # managed_groups returns array of hashes with symbol keys
    client.managed_groups.map { |group| group[:username] }
  end
end
