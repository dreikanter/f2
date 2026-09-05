class LlmClient
  # Supplies evidence to models that cannot call tools. Fetches share the run's
  # time and tool allowance, including the tool's public-URL and redirect guards.
  class SuppliedPages
    MAX_PAGES = 3

    def initialize(budget:)
      @fetcher = Tools::WebFetch.new(budget: budget)
    end

    def fetch(prompt)
      urls = URI::DEFAULT_PARSER.extract(prompt.to_s, %w[http https]).uniq.first(MAX_PAGES)
      urls.each_with_object([]) do |url, pages|
        result = @fetcher.execute(url: url)
        break pages if result.is_a?(RubyLLM::Tool::Halt)

        pages << { url: url, result: JSON.parse(result) }
      end
    end
  end
end
