# Per-model token rates loaded from config/llm_rates.yml.
#
# Computes the USD cost of a single LLM call from the token counts
# ruby_llm reports. Models or providers without an entry yield a zero
# cost — callers should treat that as "unknown" rather than "free" when
# surfacing spend.
class LlmClient::RateTable
  PATH = Rails.root.join("config/llm_rates.yml")

  Rate = Data.define(
    :input_per_million,
    :output_per_million,
    :cache_write_per_million,
    :cache_read_per_million
  )

  Usage = Data.define(
    :input_tokens,
    :output_tokens,
    :cache_write_tokens,
    :cache_read_tokens
  )

  class << self
    def rate_for(provider:, model:)
      entry = table.dig(provider.to_s, model.to_s)
      return nil unless entry

      Rate.new(
        input_per_million: entry["input_per_million"].to_f,
        output_per_million: entry["output_per_million"].to_f,
        cache_write_per_million: entry["cache_write_per_million"].to_f,
        cache_read_per_million: entry["cache_read_per_million"].to_f
      )
    end

    def cost_for(provider:, model:, usage:)
      rate = rate_for(provider: provider, model: model)
      return 0.0 unless rate

      cents = 0.0
      cents += usage.input_tokens.to_i * rate.input_per_million
      cents += usage.output_tokens.to_i * rate.output_per_million
      cents += usage.cache_write_tokens.to_i * rate.cache_write_per_million
      cents += usage.cache_read_tokens.to_i * rate.cache_read_per_million
      (cents / 1_000_000.0).round(6)
    end

    def reload!
      @table = nil
    end

    private

    def table
      @table ||= load_table
    end

    def load_table
      raw = File.read(PATH)
      parsed = YAML.safe_load(raw, permitted_classes: [Symbol, Float])
      parsed || {}
    end
  end
end
