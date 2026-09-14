# Reads the SDK's shared registry for model selectors.
module LlmModels
  def self.for_provider(provider)
    if RubyLLM::ActiveRecord::Model.exists?
      RubyLLM::ActiveRecord::Model.listed.where(provider: provider).map(&:to_llm)
    else
      RubyLLM::Models.new([]).load_from_json.by_provider(provider).to_a
    end
  end

  # Unlisted models stay in the table so saved selections keep resolving, so
  # the dev summary reports them apart from what selectors offer.
  def self.counts_by_provider
    totals = RubyLLM::ActiveRecord::Model.group(:provider).count
    listed = RubyLLM::ActiveRecord::Model.listed.group(:provider).count

    totals.keys.sort.map do |provider|
      listed_count = listed.fetch(provider, 0)
      { provider: provider, listed: listed_count, unlisted: totals.fetch(provider) - listed_count }
    end
  end

  def self.for_feed(provider)
    for_provider(provider).reject do |model|
      outputs = model.modalities.output
      outputs.any? && !outputs.include?("text")
    end
  end
end
