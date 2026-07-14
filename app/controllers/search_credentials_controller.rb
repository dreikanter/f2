class SearchCredentialsController < ApplicationController
  include StatePolling

  def index
    authorize SearchCredential
    @search_credentials = scope.order(created_at: :desc)
  end

  def show
    @search_credential = find_credential
    authorize @search_credential
  end

  def new
    @search_credential = SearchCredential.new(provider: params[:provider] || WebSearchProvider::REGISTRY.keys.first)
    authorize @search_credential
  end

  def create
    @search_credential = build_credential
    authorize @search_credential

    if @search_credential.save
      SearchCredentialValidationJob.perform_later(@search_credential)
      redirect_to search_credential_path(@search_credential)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @search_credential = find_credential
    authorize @search_credential
  end

  def update
    @search_credential = find_credential
    authorize @search_credential

    key_changed = credential_data_from_params["api_key"].present?
    if @search_credential.update(updated_credential_attrs(key_changed: key_changed))
      SearchCredentialValidationJob.perform_later(@search_credential) if key_changed
      redirect_to search_credential_path(@search_credential)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    credential = find_credential
    authorize credential
    credential.destroy!
    redirect_to search_credentials_path, success: "Search credential '#{credential.display_name}' deleted."
  end

  private

  def updated_credential_attrs(key_changed:)
    attrs = { display_name: credential_params[:display_name] }
    return attrs unless key_changed

    attrs.merge(credential_data: credential_data_from_params, state: :pending)
  end

  def build_credential
    Current.user.search_credentials.build(
      provider: credential_params[:provider],
      display_name: credential_params[:display_name],
      credential_data: credential_data_from_params,
      state: :pending
    )
  end

  def find_credential
    scope.find(params[:id])
  end

  def scope
    policy_scope(SearchCredential)
  end

  def credential_params
    params.require(:search_credential).permit(:provider, :display_name, credential_data: {})
  end

  def credential_data_from_params
    raw = credential_params[:credential_data]
    case raw
    when ActionController::Parameters then raw.to_unsafe_h
    when Hash then raw
    else {}
    end
  end
end
