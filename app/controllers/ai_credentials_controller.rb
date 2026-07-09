class AiCredentialsController < ApplicationController
  include StatePolling

  def index
    authorize AiCredential
    @ai_credentials = scope.order(created_at: :desc)
  end

  def show
    @ai_credential = find_credential
    @feed = detour_feed
    authorize @ai_credential
  end

  def new
    @ai_credential = AiCredential.new(provider: params[:provider] || LlmProvider.names.first)
    @feed = detour_feed
    authorize @ai_credential
  end

  def create
    @ai_credential = build_credential
    @feed = detour_feed
    authorize @ai_credential

    if @ai_credential.save
      @feed&.update_column(:ai_credential_id, @ai_credential.id)
      AiCredentialValidationJob.perform_later(@ai_credential)
      redirect_to ai_credential_path(@ai_credential, feed_id: @feed&.id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @ai_credential = find_credential
    authorize @ai_credential
  end

  def update
    @ai_credential = find_credential
    authorize @ai_credential

    if @ai_credential.update(updated_credential_attrs)
      AiCredentialValidationJob.perform_later(@ai_credential)
      redirect_to ai_credential_path(@ai_credential)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    credential = find_credential
    authorize credential
    credential.destroy!
    redirect_to ai_credentials_path, success: "AI credential '#{credential.display_name}' deleted."
  end

  private

  # The draft feed that detoured here from the feed form (feed_id round-trip),
  # or nil when entered directly.
  def detour_feed
    return nil if params[:feed_id].blank?

    Current.user.feeds.find_by(id: params[:feed_id])
  end

  def updated_credential_attrs
    attrs = { display_name: credential_params[:display_name], state: :pending }
    data = credential_data_from_params
    attrs[:credential_data] = data if data["api_key"].present?
    attrs
  end

  def build_credential
    Current.user.ai_credentials.build(
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
    policy_scope(AiCredential)
  end

  def credential_params
    params.require(:ai_credential).permit(:provider, :display_name, credential_data: {})
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
