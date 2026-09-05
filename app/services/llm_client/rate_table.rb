# Estimates use exact model prices; missing rates remain unknown.
class LlmClient::RateTable
  PATH = Rails.root.join("config/llm_rates.yml")

  Rate = Data.define(
    :input_per_million,
    :output_per_million,
    :cache_write_per_million,
    :cache_read_per_million
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

    def cost_for(provider:, model:, usage:, pricing: nil)
      if pricing.nil?
        rate = rate_for(provider: provider, model: model)
        return unless rate

        pricing = {
          "input" => rate.input_per_million, "output" => rate.output_per_million,
          "cache_write" => rate.cache_write_per_million, "cache_read" => rate.cache_read_per_million
        }
      end

      dollars_per_million = 0.0
      %w[input output cache_write cache_read].each do |kind|
        count = usage.public_send("#{kind}_tokens").to_i
        next if count.zero?

        price = pricing[kind]
        return unless price.is_a?(Numeric) && price >= 0

        dollars_per_million += count * price
      end
      ((dollars_per_million / 1_000_000.0) * 100).round
    end

    def reload!
      @table = nil
    end

    private

    def table
      @table ||= load_table
    end

    def load_table
      return {} unless File.exist?(PATH)

      raw = File.read(PATH)
      parsed = YAML.safe_load(raw, permitted_classes: [Symbol, Float])
      parsed || {}
    end
  end
end
