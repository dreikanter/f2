class Admin::SearchCredentialsController < ApplicationController
  def show
    @search_credential = SearchCredential.find(params[:id])
    authorize [:admin, @search_credential]
  end
end
