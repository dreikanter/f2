class Development::ComponentsController < ApplicationController
  def show
    authorize :admin, :dev?
  end
end
