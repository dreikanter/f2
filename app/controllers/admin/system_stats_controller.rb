class Admin::SystemStatsController < ApplicationController
  def show
    authorize :admin, :show?
    @disk_usage = Rails.cache.fetch("admin/system_stats", expires_in: 5.minutes) do
      DiskUsageService.new.call
    end
  end
end
