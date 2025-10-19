class Onboarding::AccessTokensController < Onboarding::BaseController
  def create
    @token = params.require(:token)
    @host = params.require(:host)
    @owner = params.require(:owner)

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

  private

  def unique_name
    @unique_name ||= begin
      host_config = AccessToken::FREEFEED_HOSTS.values.find { |h| h[:url] == host }
      domain_name = host_config[:domain]
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
    @token
  end

  def host
    @host
  end

  def owner
    @owner
  end
end
