# Shared CRUD for the provider credential types (AI and web search). Both wrap
# a user-owned API key that gets re-checked asynchronously whenever it changes,
# and both can be entered mid-feed-setup through a feed_id round-trip.
#
# Subclasses declare their model and validation job, plus the two things that
# can't be derived from the model: the provider chosen by default on the new
# form, and the noun used in user-facing copy.
class CredentialsController < ApplicationController
  include StatePolling

  class_attribute :credential_class, instance_writer: false
  class_attribute :validation_job, instance_writer: false

  def index
    authorize credential_class
    @credentials = scope.order(created_at: :desc)
  end

  def show
    @credential = find_credential
    @feed = detour_feed
    authorize @credential
  end

  def new
    @credential = credential_class.new(provider: params[:provider] || default_provider)
    @feed = detour_feed
    authorize @credential
  end

  def create
    @credential = build_credential
    @feed = detour_feed
    authorize @credential

    if @credential.save
      @feed&.update_column(feed_foreign_key, @credential.id)
      @credential.validate_async(validation_job)
      redirect_to polymorphic_path(@credential, feed_id: @feed&.id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @credential = find_credential
    authorize @credential
  end

  def update
    @credential = find_credential
    authorize @credential

    # A blank key field means "keep the current key", so only a submitted key
    # is worth re-checking — renaming a credential leaves its state alone.
    key_changed = credential_data_from_params["api_key"].present?

    if @credential.update(updated_credential_attrs(key_changed: key_changed))
      @credential.validate_async(validation_job) if key_changed
      redirect_to polymorphic_path(@credential)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    credential = find_credential
    authorize credential
    credential.destroy!
    redirect_to polymorphic_path(credential_class), success: "#{credential_noun} '#{credential.display_name}' deleted."
  end

  private

  def default_provider
    raise NotImplementedError, "#{self.class.name} must implement #default_provider"
  end

  def credential_noun
    raise NotImplementedError, "#{self.class.name} must implement #credential_noun"
  end

  # The draft feed that detoured here from the feed form (feed_id round-trip),
  # or nil when entered directly.
  def detour_feed
    return nil if params[:feed_id].blank?

    Current.user.feeds.find_by(id: params[:feed_id])
  end

  def updated_credential_attrs(key_changed:)
    attrs = { display_name: credential_params[:display_name] }
    return attrs unless key_changed

    attrs.merge(
      credential_data: credential_data_from_params,
      state: :pending,
      validation_started_at: nil,
      validation_run_id: nil
    )
  end

  def build_credential
    owned_credentials.build(
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
    policy_scope(credential_class)
  end

  def owned_credentials
    Current.user.public_send(credential_class.model_name.plural)
  end

  def feed_foreign_key
    :"#{credential_class.model_name.param_key}_id"
  end

  def credential_params
    params.require(credential_class.model_name.param_key).permit(:provider, :display_name, credential_data: {})
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
