class Admin::SystemStatsController < ApplicationController
  def show
    authorize :admin, :show?
    @disk_usage = DiskUsageService.new.call
  end
end
