class AccessTokens::GroupsController < ApplicationController
  def index
    @token = Current.user.access_tokens.find_by(id: params[:access_token_id])
    @feed = Current.user.feeds.find_by(id: params[:feed_id]) || Current.user.feeds.build
    @groups, @token_error = fetch_groups_with_cache(@token) if @token&.active?
    @groups ||= []

    render turbo_stream: turbo_stream.replace(
      "target-group-selector",
      partial: "feeds/target_group_selector",
      locals: { feed: @feed, groups: @groups, token: @token, token_error: @token_error }
    )
  end

  private

  def fetch_groups_with_cache(token)
    groups = Rails.cache.fetch(
      "access_token_groups/#{token.id}",
      expires_in: 10.minutes,
      race_condition_ttl: 5.seconds,
      error_handler: ->(exception:, key:, **) {
        Rails.logger.error("Cache error for key #{key}: #{exception.message}")
      }
    ) do
      fetch_groups_from_freefeed(token)
    end
    [groups, nil]
  rescue FreefeedClient::UnauthorizedError => e
    Rails.logger.error("Unauthorized error for token #{token.id}: #{e.message}")
    [[], :unauthorized]
  rescue StandardError => e
    Rails.logger.error("Failed to fetch groups for token #{token.id}: #{e.message}")
    [[], :api_error]
  end

  def fetch_groups_from_freefeed(token)
    token.build_client.managed_groups.map { |group| group[:username] }
  end
end
