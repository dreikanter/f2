module WebSearch
  module Provider
    # serper.dev — Google SERP results.
    class Serper < Base
      ENV_KEY = "SERPER_API_KEY"
      ENDPOINT = "https://google.serper.dev/search"

      private

      def request(query, count)
        http.post(
          ENDPOINT,
          body: { q: query, num: count }.to_json,
          headers: { "X-API-KEY" => api_key, "Content-Type" => "application/json" }
        )
      end

      def map_results(json)
        Array(json["organic"]).map do |result|
          Result.new(title: result["title"].to_s, url: result["link"].to_s, snippet: result["snippet"].to_s)
        end
      end
    end
  end
end
