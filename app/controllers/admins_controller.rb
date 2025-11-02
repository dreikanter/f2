class AdminsController < ApplicationController
  layout "tailwind"

  def show
    authorize :admin, :show?
  end
end
