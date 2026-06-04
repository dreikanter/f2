class Development::ComponentsController < ApplicationController
  def show
    authorize :dev, :show?
  end
end
