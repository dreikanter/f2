class Admin::SystemStatsController < ApplicationController
  layout "tailwind"

  def show
    authorize :admin, :show?
    @disk_usage = Rails.cache.fetch("admin/system_stats/v3", expires_in: 5.minutes) do
      DiskUsageService.new.call
    end
  end
end
