module WebSearch
  module Provider
    # Brave Search API — independent web index.
    class Brave < Base
      ENV_KEY = "BRAVE_SEARCH_API_KEY"
      ENDPOINT = "https://api.search.brave.com/res/v1/web/search"

      private

      def request(query, count)
        http.get(
          "#{ENDPOINT}?#{URI.encode_www_form(q: query, count: count)}",
          headers: { "X-Subscription-Token" => api_key, "Accept" => "application/json" }
        )
      end

      def map_results(json)
        Array(json.dig("web", "results")).map do |result|
          Result.new(title: result["title"].to_s, url: result["url"].to_s, snippet: result["description"].to_s)
        end
      end
    end
  end
end
