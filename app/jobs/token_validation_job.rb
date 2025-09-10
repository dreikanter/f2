class TokenValidationJob < ApplicationJob
  queue_as :default

  def perform(access_token)
    return unless access_token.token_value.present?

    begin
      response = validate_freefeed_token(access_token.token_value)

      if response[:success] && response[:username]
        access_token.update!(status: :active, owner: response[:username])
      else
        access_token.inactive!
      end
    rescue => e
      access_token.inactive!
    end
  end

  private

  def validate_freefeed_token(token)
    response = make_api_request(token)
    parse_api_response(response)
  rescue JSON::ParserError
    { success: false, error: "Invalid JSON response" }
  rescue HttpClient::TooManyRedirectsError => e
    { success: false, error: "Too many redirects" }
  rescue HttpClient::Error => e
    { success: false, error: e.message }
  rescue => e
    { success: false, error: e.message }
  end

  def make_api_request(token)
    http_client.get(
      "#{freefeed_host}/v4/users/whoami",
      headers: {
        "Authorization" => "Bearer #{token}",
        "Accept" => "application/json",
        "User-Agent" => "FreeFeed-Token-Validator"
      }
    )
  end

  def parse_api_response(response)
    if response.success?
      parse_success_response(response.body)
    else
      { success: false, error: "HTTP #{response.status}: #{response.body}" }
    end
  end

  def parse_success_response(body)
    data = JSON.parse(body)
    username = data.dig("users", "username")

    if username
      { success: true, username: username }
    else
      { success: false, error: "Invalid response format" }
    end
  end

  def http_client
    @http_client ||= HttpClient::FaradayAdapter.new
  end

  def freefeed_host
    ENV.fetch("FREEFEED_HOST")
  end
end
