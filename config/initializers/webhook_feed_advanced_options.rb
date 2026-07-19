# Webhook feeds ingest explicitly submitted posts, so pull-feed filtering options
# do not apply. Strip those form attributes at the controller boundary even when
# a client submits them directly.
module WebhookFeedAdvancedOptions
  ADVANCED_OPTION_KEYS = %w[
    import_after_enabled
    import_after_date
    import_after_time
    images_only
  ].freeze

  private

  def create_feed_params
    permitted = super
    webhook_profile_submitted? ? permitted.except(*ADVANCED_OPTION_KEYS) : permitted
  end

  def update_feed_params
    permitted = super
    @feed&.sourceless? ? permitted.except(*ADVANCED_OPTION_KEYS) : permitted
  end

  def webhook_profile_submitted?
    params.dig(:feed, :feed_profile_key) == "webhook"
  end
end

Rails.application.config.to_prepare do
  FeedsController.prepend(WebhookFeedAdvancedOptions) unless FeedsController < WebhookFeedAdvancedOptions
end
