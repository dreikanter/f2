class SearchCredentials::DefaultsController < ApplicationController
  def update
    authorize credential, :update?
    credential.make_default!

    respond_to do |format|
      format.turbo_stream do
        flash.now[:success] = "'#{credential.display_name}' is now the default search credential."
        @search_credentials = policy_scope(SearchCredential).order(created_at: :desc)
      end
      format.html do
        redirect_to search_credentials_path,
                    success: "'#{credential.display_name}' is now the default search credential."
      end
    end
  end

  private

  def credential
    @credential ||= scope.find(params[:search_credential_id])
  end

  def scope
    policy_scope(SearchCredential)
  end
end
