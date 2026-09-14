# Reads the SDK's shared registry for model selectors.
module LlmModels
  def self.for_provider(provider)
    if RubyLLM::ActiveRecord::Model.exists?
      RubyLLM::ActiveRecord::Model.listed.where(provider: provider).map(&:to_llm)
    else
      RubyLLM::Models.new([]).load_from_json.by_provider(provider).to_a
    end
  end

  def self.for_feed(provider)
    for_provider(provider).reject do |model|
      outputs = model.modalities.output
      outputs.any? && !outputs.include?("text")
    end
  end
end
