class LlmCredentialsController < ApplicationController
  def index
    authorize LlmCredential
    @llm_credentials = scope.order(created_at: :desc)
  end

  def show
    @llm_credential = find_credential
    @feed = scoped_feed(params[:feed_id])
    authorize @llm_credential
  end

  def new
    @llm_credential = LlmCredential.new(provider: params[:provider] || LlmProvider.names.first)
    @feed = scoped_feed(params[:feed_id])
    authorize @llm_credential
  end

  def create
    @llm_credential = build_credential
    @feed = scoped_feed(params[:feed_id])
    authorize @llm_credential

    if @llm_credential.save
      @feed&.update_column(:llm_credential_id, @llm_credential.id)
      LlmCredentialValidationJob.perform_later(@llm_credential)
      redirect_to llm_credential_path(@llm_credential, feed_id: @feed&.id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @llm_credential = find_credential
    authorize @llm_credential
  end

  def update
    @llm_credential = find_credential
    authorize @llm_credential

    if @llm_credential.update(updated_credential_attrs)
      LlmCredentialValidationJob.perform_later(@llm_credential)
      redirect_to llm_credential_path(@llm_credential)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    credential = find_credential
    authorize credential
    credential.destroy!
    redirect_to llm_credentials_path, success: "AI credential '#{credential.display_name}' deleted."
  end

  private

  def scoped_feed(feed_id)
    return nil if feed_id.blank?

    Current.user.feeds.find_by(id: feed_id)
  end

  def updated_credential_attrs
    attrs = { display_name: credential_params[:display_name], state: :pending }
    data = credential_data_from_params
    attrs[:credential_data] = data if data["api_key"].present?
    attrs
  end

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
end
