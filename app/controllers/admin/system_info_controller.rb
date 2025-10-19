class Admin::SystemInfoController < ApplicationController
  before_action :require_admin

  def show
    @disk_usage = DiskUsageService.call
  end

  private

  def require_admin
    redirect_to root_path unless Current.user.admin?
  end
end
