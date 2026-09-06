# Task modes are advisory evidence about the API served by this provider.
class PublishedModelTasks
  URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json".freeze
  CACHE_KEY = "published-model-tasks/v1".freeze

  def lookup(provider, model_id)
    ids = %w[openrouter moonshot].include?(provider) ? ["#{provider}/#{model_id}"] : [model_id, "#{provider}/#{model_id}"]
    providers = provider == "openai" ? %w[openai text-completion-openai] : [provider]
    modes = ids.filter_map do |id|
      entry = catalog[id]
      next unless entry.is_a?(Hash) && providers.include?(entry["litellm_provider"])

      mode = entry["mode"]
      mode if mode.is_a?(String) && mode.present?
    end.uniq
    # Conflicting aliases cannot establish a task classification.
    return unless modes.one?

    { "source" => "litellm", "mode" => modes.first }
  end

  private

  def catalog
    @catalog ||= PublishedModelCatalog.fetch(URL, CACHE_KEY) do |data|
      data.values.all? { |entry| entry.is_a?(Hash) }
    end
  end
end
