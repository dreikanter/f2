class FreefeedSubscriberCount
  def initialize(access_token)
    @access_token = access_token
  end

  def call(username)
    response = http_client.get(
      "#{access_token.host}/v2/users/#{CGI.escapeURIComponent(username)}",
      headers: headers
    )

    handle_response(response)
  rescue HttpClient::Error => e
    raise FreefeedClient::Error, "Failed to fetch subscriber count: #{e.message}"
  end

  private

  attr_reader :access_token

  def http_client
    @http_client ||= HttpClient.build(FreefeedClient::DEFAULT_OPTIONS)
  end

  def headers
    {
      "Authorization" => "Bearer #{access_token.encrypted_token}",
      "Accept" => "application/json",
      "User-Agent" => FreefeedClient::USER_AGENT
    }
  end

  def handle_response(response)
    case response.status
    when 200
      parse(response.body)
    when 401
      raise FreefeedClient::UnauthorizedError, error_message(response) || "Unauthorized"
    when 403
      raise FreefeedClient::ForbiddenError, error_message(response) || "Forbidden"
    when 404
      raise FreefeedClient::NotFoundError, error_message(response) || "Resource not found"
    when 429
      retry_after = response.headers["retry-after"].to_i
      retry_after = FreefeedClient::DEFAULT_RETRY_AFTER unless retry_after.positive?
      RateLimit.penalize(:freefeed, subject: access_token.rate_limit_subject, retry_after: retry_after)
      raise RateLimit::Throttled.new(retry_after: retry_after)
    else
      raise FreefeedClient::Error, "HTTP #{response.status}: #{response.body}"
    end
  end

  def parse(body)
    data = JSON.parse(body)
    count = data.dig("users", "statistics", "subscribers")
    raise FreefeedClient::Error, "Invalid user response format" if count.nil?

    Integer(count)
  rescue JSON::ParserError, ArgumentError => e
    raise FreefeedClient::Error, "Invalid user response: #{e.message}"
  end

  def error_message(response)
    JSON.parse(response.body).fetch("err", nil) if response.body.present?
  rescue JSON::ParserError
    nil
  end
end
