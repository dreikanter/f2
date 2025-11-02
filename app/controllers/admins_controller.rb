class AdminsController < ApplicationController

  def show
    authorize :admin, :show?
  end
end
