class Admin::SystemStatsController < ApplicationController
  def show
    authorize :access, :dev?
    @config_checks = config_checks
    @release_info = release_info
    @disk_usage = Rails.cache.fetch("admin/system_stats/v3", expires_in: 5.minutes) do
      DiskUsageService.new.call
    end
  end

  private

  def config_checks
    [
      {
        key: "resend_key",
        label: "Resend key present",
        ok: Rails.application.credentials.dig(:resend_api_token).present?
      }
    ]
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
