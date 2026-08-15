module WebSearchProvider
  # Brave Search API — independent web index.
  class Brave < Base
    ENDPOINT = "https://api.search.brave.com/res/v1/web/search"
    # Brave answers a rejected subscription token with 422 — the same status
    # it uses for an ordinary bad parameter — so only the body separates a
    # dead key from a malformed query.
    REJECTED_KEY_STATUS = 422
    REJECTED_KEY_CODE = "SUBSCRIPTION_TOKEN_INVALID".freeze
    AUTH_COMPONENT = "authentication".freeze

    private

    def auth_error?(response)
      return true if super
      return false unless response.status == REJECTED_KEY_STATUS

      rejected_key?(response.body)
    end

    # Matches the documented code, and any other failure Brave attributes to
    # authentication, so a renamed token error still reads as a dead key.
    def rejected_key?(body)
      error = JSON.parse(body.to_s)["error"]
      return false unless error.is_a?(Hash)

      error["code"] == REJECTED_KEY_CODE || error.dig("meta", "component") == AUTH_COMPONENT
    rescue JSON::ParserError
      false
    end

    def request(query, count)
      http.get(
        "#{ENDPOINT}?#{URI.encode_www_form(q: query, count: count)}",
        headers: {
          "X-Subscription-Token" => api_key,
          "Accept" => "application/json"
        }
      )
    end

    def map_results(json)
      Array(json.dig("web", "results")).map do |result|
        Result.new(
          title: result["title"].to_s,
          url: result["url"].to_s,
          snippet: result["description"].to_s
        )
      end
    end
  end
end
