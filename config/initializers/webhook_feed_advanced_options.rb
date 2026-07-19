# Webhook feeds ingest explicitly submitted posts, so pull-feed filtering options
# must never affect them. Keep persisted values normalized and make reads inert
# even for records created before this guard existed.
module WebhookFeedAdvancedOptions
  extend ActiveSupport::Concern

  prepended do
    before_validation :clear_webhook_advanced_options
  end

  def import_after_enabled
    sourceless? ? false : super
  end

  def import_after_date
    sourceless? ? nil : super
  end

  def import_after_time
    sourceless? ? nil : super
  end

  def images_only
    sourceless? ? false : super
  end

  private

  def clear_webhook_advanced_options
    return unless sourceless?

    self[:import_after_enabled] = false
    self[:import_after_date] = nil
    self[:import_after_time] = nil
    self[:images_only] = false
  end
end

Rails.application.config.to_prepare do
  Feed.prepend(WebhookFeedAdvancedOptions) unless Feed < WebhookFeedAdvancedOptions
end
