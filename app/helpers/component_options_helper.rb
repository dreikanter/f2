module ComponentOptionsHelper
  def loader_options
    available_options(Loader::AVAILABLE_OPTIONS, "loaders")
  end

  def processor_options
    available_options(Processor::AVAILABLE_OPTIONS, "processors")
  end

  def normalizer_options
    available_options(Normalizer::AVAILABLE_OPTIONS, "normalizers")
  end

  def access_token_options
    Current.user.access_tokens.active.map do |token|
      ["#{token.name} (#{token.host})", token.id]
    end
  end

  def has_active_tokens?
    Current.user.access_tokens.active.exists?
  end

  def feed_profile_options
    FeedProfile.all.map do |profile|
      [t("feed_profiles.#{profile.name}"), profile.id]
    end
  end

  def human_readable_cron(cron_expression)
    return "not configured" if cron_expression.blank?

    case cron_expression
    when "*/30 * * * *"
      "every 30 minutes"
    when "0 * * * *"
      "every hour"
    when "0 */6 * * *"
      "every 6 hours"
    when "0 0 * * *"
      "daily at midnight"
    else
      "using custom schedule"
    end
  end

  def cron_expression_options
    [
      "*/30 * * * *",
      "0 * * * *",
      "0 */6 * * *",
      "0 0 * * *"
    ].map do |cron|
      [human_readable_cron(cron).capitalize, cron]
    end
  end

  def cron_expression_details(cron_expression)
    return nil if cron_expression.blank?

    case cron_expression
    when "*/30 * * * *", "0 * * * *", "0 */6 * * *", "0 0 * * *"
      nil # No additional details needed for common patterns
    else
      cron_expression # Show the raw cron for custom patterns
    end
  end

  private

  def available_options(keys, i18n_prefix)
    keys.map do |key|
      [t("#{i18n_prefix}.#{key}"), key]
    end
  end
end
