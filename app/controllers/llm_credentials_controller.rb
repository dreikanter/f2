class LlmCredentialsController < ApplicationController
  def index
    authorize LlmCredential
    @llm_credentials = scope.order(created_at: :desc)
  end

  def show
    @llm_credential = find_credential
    @return_to = params[:return_to]
    authorize @llm_credential
  end

  def new
    @llm_credential = LlmCredential.new(provider: params[:provider] || LlmProvider.names.first)
    @return_to = safe_return_to
    authorize @llm_credential
  end

  def create
    @llm_credential = build_credential
    @return_to = safe_return_to
    authorize @llm_credential

    if @llm_credential.save
      LlmCredentialValidationJob.perform_later(@llm_credential)
      redirect_to llm_credential_path(@llm_credential, return_to: @return_to)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    credential = find_credential
    authorize credential
    credential.destroy!
    redirect_to llm_credentials_path, notice: "AI credential '#{credential.display_name}' has been deleted."
  end

  private

  def build_credential
    Current.user.llm_credentials.build(
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
    policy_scope(LlmCredential)
  end

  def credential_params
    params.require(:llm_credential).permit(:provider, :display_name, credential_data: {})
  end

  def credential_data_from_params
    raw = credential_params[:credential_data]
    case raw
    when ActionController::Parameters then raw.to_unsafe_h
    when Hash then raw
    else {}
    end
  end

  # Only accept same-host paths so a hostile redirect can't smuggle
  # users off-site after they save a credential.
  def safe_return_to
    candidate = params[:return_to].to_s
    candidate if candidate.start_with?("/") && !candidate.start_with?("//")
  end
end
