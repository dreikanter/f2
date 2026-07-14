class SearchCredentials::ValidationsController < ApplicationController
  def show
    search_credential = policy_scope(SearchCredential).find(params[:search_credential_id])
    authorize search_credential, :show?, policy_class: SearchCredentialPolicy

    return head :no_content if search_credential.pending? || search_credential.validating?

    render turbo_stream: turbo_stream.update(
      "search-credential-show",
      partial: "search_credentials/show_content",
      locals: { search_credential: search_credential, feed_id: params[:feed_id] }
    )
  end
end
