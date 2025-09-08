require "net/http"

class TokenValidationJob < ApplicationJob
  queue_as :default

  def perform(access_token)
    return unless access_token.token_value.present?

    begin
      # Use the stored encrypted token value to validate
      response = validate_freefeed_token(access_token.token_value)

      if response[:success] && response[:username]
        access_token.update!(status: :active, owner: response[:username])
        broadcast_status_update(access_token, success: true)
      else
        access_token.inactive!
        broadcast_status_update(access_token, success: false, error: response[:error])
      end
    rescue => e
      access_token.inactive!
      broadcast_status_update(access_token, success: false, error: "Validation failed: #{e.message}")
    end
  end

  private

  def validate_freefeed_token(token)
    response = make_api_request(token)
    parse_api_response(response)
  rescue JSON::ParserError
    { success: false, error: "Invalid JSON response" }
  rescue => e
    { success: false, error: e.message }
  end

  def make_api_request(token)
    uri = URI("#{freefeed_host}/v4/users/whoami")
    http = configure_http_client(uri)
    request = build_request(uri, token)
    http.request(request)
  end

  def configure_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http
  end

  def build_request(uri, token)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    request["User-Agent"] = "FreeFeed-Token-Validator"
    request
  end

  def parse_api_response(response)
    if response.code == "200"
      parse_success_response(response.body)
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
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

  def freefeed_host
    ENV.fetch("FREEFEED_HOST", "https://freefeed.net")
  end

  def broadcast_status_update(access_token, success:, error: nil)
    Turbo::StreamsChannel.broadcast_update_to(
      "access_token_#{access_token.id}",
      target: ActionView::RecordIdentifier.dom_id(access_token, :status),
      partial: "access_tokens/status",
      locals: { token: access_token, success: success, error: error }
    )
  end
end
