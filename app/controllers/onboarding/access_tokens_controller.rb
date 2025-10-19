class Onboarding::AccessTokensController < ApplicationController
  skip_onboarding_redirect

  def show
    @host = AccessToken::FREEFEED_HOSTS["production"]
    @token = ""
  end

  def create
    case params.require(:subcommand)
    when "validate"
      validate_token
    when "save"
      save_token
    end
  end

  private

  def validate_token
    token = params.require(:token)
    host = params.require(:host)

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
    render_error(token, host, "Invalid token or insufficient permissions")
  rescue FreefeedClient::Error => e
    render_error(token, host, "Failed to validate token: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("Token validation error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render_error(token, host, "An unexpected error occurred during validation")
  end

  def save_token
    token_value = params.require(:token)
    host = params.require(:host)
    owner = params.require(:owner)

    # Generate unique token name
    base_name = "#{owner} at #{host.sub('https://', '')}"
    token_name = generate_unique_name(base_name)

    # Create the access token
    access_token = Current.user.access_tokens.create!(
      name: token_name,
      host: host,
      owner: owner,
      token: token_value,
      status: :active
    )

    # Update onboarding to associate with this token
    onboarding = Current.user.onboarding
    onboarding.update!(access_token: access_token)

    # Redirect to feed setup step
    redirect_to onboarding_feed_path, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    render_error(token_value, host, "Failed to save token: #{e.message}", owner: owner)
  rescue StandardError => e
    Rails.logger.error("Token creation error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render_error(token_value, host, "An unexpected error occurred while saving the token", owner: owner)
  end

  def generate_unique_name(base_name)
    return base_name unless Current.user.access_tokens.exists?(name: base_name)

    index = 2
    loop do
      candidate_name = "#{base_name} (#{index})"
      return candidate_name unless Current.user.access_tokens.exists?(name: candidate_name)

      index += 1
    end
  end

  def render_error(token, host, message, owner: nil)
    if owner.present?
      # Error during save - show token details with error
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
    else
      # Error during validation - show validation form with error
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
  end
end
