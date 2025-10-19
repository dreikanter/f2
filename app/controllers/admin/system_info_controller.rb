class Admin::SystemInfoController < ApplicationController
  def show
    authorize :admin, :show?
    @disk_usage = DiskUsageService.call
  end
end
