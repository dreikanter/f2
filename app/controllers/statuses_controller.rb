class StatusesController < ApplicationController

  def show
    @user = Current.user
  end
end
