class Admin::AiCredentialsController < ApplicationController
  def show
    @ai_credential = AiCredential.find(params[:id])
    authorize [:admin, @ai_credential]
  end
end
