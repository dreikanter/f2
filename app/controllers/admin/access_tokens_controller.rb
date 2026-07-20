class Admin::AccessTokensController < ApplicationController
  def show
    @access_token = AccessToken.find(params[:id])
    authorize [:admin, @access_token]
  end
end
