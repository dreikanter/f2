class DevtoolsController < ApplicationController
  def show
    authorize :access, :dev?
  end
end
