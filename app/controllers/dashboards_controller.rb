class DashboardsController < ApplicationController
  before_action :require_authentication

  def show
    @user = Current.user
    @access_tokens_count = @user.access_tokens.active.count
  end
end
