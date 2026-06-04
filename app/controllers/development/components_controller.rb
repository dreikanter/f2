class Development::ComponentsController < ApplicationController
  def show
    authorize :access, :dev?
  end
end
