class Onboarding::AccessTokensController < Onboarding::BaseController
  def create
    case params.require(:subcommand)
    when "validate"
      validate_token
    when "save"
      save_token
    else
      raise ArgumentError, "unsupported subcommand"
    end
  end

  private

  def validate_token
    client = FreefeedClient.new(host: host, token: token)
    user_info = client.whoami
    managed_groups = client.managed_groups

    render turbo_stream: turbo_stream.replace(
      "token-form-container",
      partial: "token_details",
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

  def save_token
    access_token = Current.user.access_tokens.create!(
      name: unique_name,
      host: host,
      owner: owner,
      token: token,
      status: :active
    )

    Current.user.onboarding.update!(access_token: access_token)
    redirect_to onboarding_feed_path, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    render_save_error("Failed to save token: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("Token creation error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render_save_error("An unexpected error occurred while saving the token")
  end

  def unique_name
    @unique_name ||= begin
      domain_name = URI.parse(host).host
      base_name = "#{owner} at #{domain_name}"
      generate_unique_name(base_name)
    end
  end

  # TBD: Refactor that
  def generate_unique_name(base_name)
    return base_name unless Current.user.access_tokens.exists?(name: base_name)

    index = 2
    loop do
      candidate_name = "#{base_name} (#{index})"
      return candidate_name unless Current.user.access_tokens.exists?(name: candidate_name)

      index += 1
    end
  end

  def render_validation_error(message)
    render turbo_stream: turbo_stream.replace(
      "token-form-container",
      partial: "form",
      locals: {
        host: host,
        token: token,
        validation_error: message
      }
    ), status: :unprocessable_entity
  end

  def render_save_error(message)
    render turbo_stream: turbo_stream.replace(
      "token-form-container",
      partial: "token_details",
      locals: {
        host: host,
        token: token,
        user_info: { username: owner },
        managed_groups: [],
        validation_error: message
      }
    ), status: :unprocessable_entity
  end

  def token
    @token ||= params.require(:token)
  end

  def host
    @host ||= params.require(:host)
  end

  def owner
    @owner ||= params.require(:owner)
  end
end
