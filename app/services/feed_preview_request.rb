class FeedPreviewRequest
  attr_reader :preview, :error

  def initialize(user:, attributes: {})
    @user = user
    @attributes = attributes.symbolize_keys
  end

  def create
    prepare
  end

  # A refresh retains the stored selections, even when provider catalogs change.
  def refresh(preview)
    raise ActiveRecord::RecordNotFound unless preview.user_id == user.id

    @previous_preview = preview
    @attributes = preview.attributes.symbolize_keys.merge(profile_key: preview.feed_profile_key)
    prepare
  end

  def profile_key
    attributes[:profile_key].to_s
  end

  private

  attr_reader :user, :attributes, :previous_preview

  def prepare
    @error = validation_error
    return self if error

    @preview = previews.find_or_initialize_by(**identity)
    @preview = start_run(@preview) if previous_preview || @preview.needs_run?
    self
  end

  def validation_error
    return :invalid_source unless FeedProfile.exists?(profile_key)
    return :invalid_source if FeedProfile.source_input_for(profile_key, preview_params).to_s.strip.blank?
    return unless FeedProfile.depends_on_ai?(profile_key)
    return :missing_ai_credentials unless user.ai_credentials.active.exists?

    :invalid_ai_selection if ai_credential.blank? || !available_ai_model?
  end

  def available_ai_model?
    return false if ai_model.blank?
    return true if ai_credential.supports_model?(ai_model)
    return true if previous_preview && previous_preview.ai_model == ai_model

    user.feeds.exists?(ai_credential: ai_credential, ai_model: ai_model)
  end

  def previews
    user.feed_previews
  end

  def identity
    @identity ||= {
      feed: feed,
      feed_profile_key: profile_key,
      params_digest: FeedPreview.digest_for(
        profile_key,
        preview_params,
        feed_id: feed&.id,
        ai_credential_id: ai_credential&.id,
        ai_model: ai_model,
        search_credential_id: search_credential&.id
      )
    }
  end

  def feed
    return previous_preview.feed if previous_preview
    return if attributes[:feed_id].blank?

    @feed ||= user.feeds.find(attributes[:feed_id])
  end

  def ai_credential
    return @ai_credential if defined?(@ai_credential)

    @ai_credential = user.ai_credentials.active.find_by(id: attributes[:ai_credential_id])
  end

  def search_credential
    return @search_credential if defined?(@search_credential)

    @search_credential =
      if previous_preview
        user.search_credentials.find_by(id: attributes[:search_credential_id])
      elsif FeedProfile.depends_on_ai?(profile_key) && attributes[:search_credential_id].present?
        user.search_credentials.active.find_by(id: attributes[:search_credential_id])
      end
  end

  def ai_model
    attributes[:ai_model].presence
  end

  def preview_params
    return previous_preview.params if previous_preview

    @preview_params ||= FeedProfile.cast_params(
      profile_key,
      (attributes[:params] || {}).deep_stringify_keys.slice(*FeedProfile.parameter_keys_for(profile_key))
    )
  end

  def start_run(preview)
    # Isolate a failed insert so recovering the winning row also works inside
    # a caller's transaction.
    FeedPreview.transaction(requires_new: true) do
      preview.assign_attributes(params: preview_params,
                                ai_credential_id: ai_credential&.id,
                                ai_model: ai_model,
                                search_credential_id: search_credential&.id)
      preview.restart!
    end
  rescue ActiveRecord::RecordNotUnique
    previews.find_by!(**identity)
  end
end
