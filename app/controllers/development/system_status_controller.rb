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
    {
      revision: AppConfig.app_revision,
      revision_short: AppConfig.app_revision_short,
      deployed_at: (Time.zone.parse(AppConfig.app_deployed_at) if AppConfig.app_deployed_at)
    }
  end
end
