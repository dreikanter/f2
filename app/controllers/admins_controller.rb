class AdminsController < ApplicationController
  def show
    authorize :access, :admin?
  end
end
