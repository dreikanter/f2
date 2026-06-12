class DevelopmentsController < ApplicationController
  def show
    authorize :access, :dev?
  end
end
