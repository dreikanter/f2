class Admin::SystemStatusController < ApplicationController
  def show
    authorize :access, :dev?
    @config_checks = config_checks
    @release_info = release_info
    @disk_usage = Rails.cache.fetch("admin/system_status/v3", expires_in: 5.minutes) do
      DiskUsageService.new.call
    end
  end

  private

  def config_checks
    [
      credential_check("resend_key", "Resend key present", :resend_api_token),
      credential_check("resend_signing_secret", "Resend signing secret present", :resend_signing_secret),
      credential_check("honeybadger_key", "Honeybadger API key present", :honeybadger, :api_key),
      background_jobs_check
    ]
  end

  # Presence checks for optional credentials. A missing key isn't an error —
  # it just means that integration is off — so it shows as neutral, not red.
  def credential_check(key, label, *path)
    status = Rails.application.credentials.dig(*path).present? ? :ok : :neutral
    { key: key, label: label, status: status }
  end

  # Jobs queue up silently when no worker is running, so confirm a SolidQueue
  # process has sent a heartbeat recently.
  def background_jobs_check
    alive = SolidQueue::Process.where(last_heartbeat_at: SolidQueue.process_alive_threshold.ago..).exists?
    { key: "background_jobs", label: "Background jobs are processing", status: alive ? :ok : :error }
  rescue StandardError => e
    Rails.error.report(e)
    { key: "background_jobs", label: "Background jobs are processing", status: :error }
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
