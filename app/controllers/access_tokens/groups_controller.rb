class AccessTokens::GroupsController < ApplicationController
  def index
    @token = Current.user.access_tokens.find_by(id: params[:access_token_id])
    @feed = Current.user.feeds.find_by(id: params[:feed_id]) || Current.user.feeds.build
    @groups = @token&.active? ? fetch_groups_with_cache(@token) : []

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
  rescue StandardError => e
    Rails.logger.error("Failed to fetch groups for token #{token.id}: #{e.message}")
    []
  end

  def fetch_groups_from_freefeed(token)
    token.build_client.managed_groups.map { |group| group[:username] }
  end
end
