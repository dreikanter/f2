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

  private

  def available_options(keys, i18n_prefix)
    keys.map do |key|
      [t("#{i18n_prefix}.#{key}"), key]
    end
  end
end
