class TokenValidationJob < ApplicationJob
  queue_as :default

  def perform(access_token)
    return unless access_token.token.present?

    begin
      # Use the raw token value to validate
      response = validate_freefeed_token(access_token.token)

      if response[:success] && response[:username]
        access_token.mark_as_active!(response[:username])
        broadcast_status_update(access_token, success: true)
      else
        access_token.mark_as_inactive!
        broadcast_status_update(access_token, success: false, error: response[:error])
      end
    rescue => e
      access_token.mark_as_inactive!
      broadcast_status_update(access_token, success: false, error: "Validation failed: #{e.message}")
    end
  end

  private

  def validate_freefeed_token(token)
    uri = URI("#{freefeed_host}/v4/users/whoami")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    request["User-Agent"] = "FreeFeed-Token-Validator"

    response = http.request(request)

    if response.code == "200"
      data = JSON.parse(response.body)
      username = data.dig("users", "username")

      if username
        { success: true, username: username }
      else
        { success: false, error: "Invalid response format" }
      end
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
    end
  rescue JSON::ParserError
    { success: false, error: "Invalid JSON response" }
  rescue => e
    { success: false, error: e.message }
  end

  def freefeed_host
    ENV.fetch("FREEFEED_HOST", "https://freefeed.net")
  end

  def broadcast_status_update(access_token, success:, error: nil)
    Turbo::StreamsChannel.broadcast_update_to(
      "access_token_#{access_token.id}",
      target: "access_token_#{access_token.id}_status",
      partial: "access_tokens/status",
      locals: { token: access_token, success: success, error: error }
    )
  end
end
