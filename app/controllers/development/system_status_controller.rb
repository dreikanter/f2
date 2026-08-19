class Development::SystemStatusController < ApplicationController
  def show
    authorize :access, :dev?
    @app_config = AppConfig.status
    @release_info = release_info
    @configuration = configuration
    @disk_usage = Rails.cache.fetch("development/system_status/v5", expires_in: 5.minutes) do
      DiskUsageService.new.call
    end
  end

  private

  def configuration
    { mailer_from: ApplicationMailer.default_params[:from] }
  end

  def release_info
    revision = ENV.fetch("APP_REVISION", nil)

    {
      revision: revision,
      revision_short: ENV.fetch("APP_REVISION_SHORT", nil).presence || revision&.first(7),
      deployed_at: deployed_at
    }
  end

  def deployed_at
    Time.zone.parse(ENV.fetch("APP_DEPLOYED_AT", nil))
  rescue ArgumentError, TypeError
    nil
  end
end
