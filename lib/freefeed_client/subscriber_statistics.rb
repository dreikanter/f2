class FreefeedClient
  module SubscriberStatistics
    def subscribers_count(username)
      response = get("/v2/users/#{CGI.escapeURIComponent(username)}/statistics")
      parse_subscribers_count_response(response.body)
    rescue HttpClient::Error => e
      raise Error, "Failed to fetch subscriber count: #{e.message}"
    end

    private

    def parse_subscribers_count_response(body)
      data = JSON.parse(body)
      count = data.dig("statistics", "subscribers")
      raise Error, "Invalid user statistics response format" if count.nil?

      Integer(count)
    rescue JSON::ParserError, ArgumentError => e
      raise Error, "Invalid user statistics response: #{e.message}"
    end
  end

  include SubscriberStatistics
end
