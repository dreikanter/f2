class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    access_token.validating! unless access_token.validating?
    user_info = fetch_user_info
    managed_groups = fetch_managed_groups

    access_token.with_lock do
      access_token.update!(status: :active, owner: user_info[:username], last_used_at: Time.current)
      access_token_detail = access_token.access_token_detail || access_token.build_access_token_detail
      access_token_detail.update!(data: { user_info: user_info, managed_groups: managed_groups })
    end
  rescue StandardError => e
    # TBD: Use more robust approach to handle errorhere
    disable_token_and_feeds
  end

  private

  def freefeed_client
    @freefeed_client ||= access_token.build_client
  end

  def disable_token_and_feeds
    access_token.with_lock do
      access_token.inactive!

      feeds = access_token.feeds.enabled
      return unless feeds.exists?

      feed_ids = feeds.pluck(:id)
      disabled_count = feeds.update_all(state: :disabled)
      create_validation_failed_event(feed_ids: feed_ids, disabled_count: disabled_count)
    end
  end

  def create_validation_failed_event(feed_ids:, disabled_count:)
    Event.create!(
      type: "access_token_validation_failed",
      user: access_token.user,
      subject: access_token,
      level: :warning,
      message: "Token validation failed. #{disabled_count} #{'feed'.pluralize(disabled_count)} disabled.",
      metadata: { disabled_feed_ids: feed_ids }
    )
  end

  def fetch_user_info
    freefeed_client.whoami
  end

  def fetch_managed_groups
    freefeed_client.managed_groups
  end
end
