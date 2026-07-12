module WebSearchProvider
  # tavily.com — LLM-oriented search with content snippets.
  class Tavily < Base
    ENDPOINT = "https://api.tavily.com/search"

    private

    def request(query, count)
      http.post(
        ENDPOINT,
        body: { query: query, max_results: count }.to_json,
        headers: {
          "Authorization" => "Bearer #{api_key}",
          "Content-Type" => "application/json"
        }
      )
    end

    def map_results(json)
      Array(json["results"]).map do |result|
        Result.new(
          title: result["title"].to_s,
          url: result["url"].to_s,
          snippet: result["content"].to_s
        )
      end
    end
  end
end
