class Onboarding::ValidationsController < Onboarding::BaseController
  def create
    @token = params.require(:token)
    @host = params.require(:host)

    client = FreefeedClient.new(host: host, token: token)
    user_info = client.whoami
    managed_groups = client.managed_groups.sort_by { |g| g[:username].downcase }

    render turbo_stream: turbo_stream.update(
      "token-form-container",
      partial: "onboarding/access_tokens/token_details",
      locals: {
        host: host,
        token: token,
        user_info: user_info,
        managed_groups: managed_groups,
        validation_error: nil
      }
    )
  rescue FreefeedClient::UnauthorizedError
    render_validation_error("Invalid token or insufficient permissions")
  rescue FreefeedClient::Error => e
    render_validation_error("Failed to validate token: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("Token validation error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render_validation_error("An unexpected error occurred during validation")
  end

  private

  def render_validation_error(message)
    render turbo_stream: turbo_stream.update(
      "token-form-container",
      partial: "onboarding/access_tokens/form",
      locals: {
        host: host,
        token: token,
        validation_error: message
      }
    ), status: :unprocessable_entity
  end

  def token
    @token
  end

  def host
    @host
  end
end
