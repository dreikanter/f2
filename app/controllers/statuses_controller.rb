class StatusesController < ApplicationController
  layout "tailwind"

  def show
    @user = Current.user
  end
end
