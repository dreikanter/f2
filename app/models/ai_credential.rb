# A user's API credential for one AI provider. Mirrors the AccessToken
# lifecycle (pending → validating → active|inactive). `credential_data`
# stores provider-specific fields (e.g. `{ "api_key" => "..." }`) and is
# encrypted at rest.
class AiCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80
  REMOVED_EVENT_TYPE = "feed_ai_credential_removed"

  belongs_to :user
  # `dependent` is handled manually by `disable_dependent_feeds` so we can
  # both nullify the reference and pull any feed left enabled out of the
  # enabled state in one pass.
  has_many :feeds

  # Rails 8 stores the encryption envelope as a JSON object
  # ({"h": {...}, "p": "<ciphertext>"}) which `jsonb` accepts natively.
  # The raw column contains only the envelope; the API key is never
  # stored in plaintext.
  encrypts :credential_data

  enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

  validates :provider, presence: true, inclusion: { in: ->(_) { LlmProvider.names } }
  validates :display_name,
            presence: true,
            length: { maximum: DISPLAY_NAME_MAX_LENGTH },
            uniqueness: { scope: [:user_id, :provider] }

  validate :api_key_present

  before_validation :assign_name_if_blank, on: :create
  before_destroy :disable_dependent_feeds

  def default?
    user.default_ai_credential_id == id
  end

  def make_default!
    user.update!(default_ai_credential: self)
  end

  def llm_provider
    LlmProvider.find(provider)
  end

  # Models this credential can actually back a feed with: the dev-verified
  # capability matrix intersected with the provider's live snapshot (spec §5).
  # Membership is qualification — a snapshot model absent from the matrix (or a
  # provider with no matrix rows) yields nothing, so nothing unverified leaks
  # into the picker or a run.
  def supported_models
    verified = LlmModelCapability.models_for(provider)
    available_models.select { |model| verified.include?(model["id"]) }
  end

  def supports_model?(model_id)
    return false if model_id.blank?

    supported_models.any? { |model| model["id"] == model_id }
  end

  # The model to fall back to when a chosen model is no longer supported: the
  # provider's configured default when it's still supported here, otherwise the
  # first supported model, or nil when the provider has no verified models.
  def default_supported_model
    provider_default = llm_provider.default_model
    return provider_default if supports_model?(provider_default)

    supported_models.first&.fetch("id")
  end

  def ruby_llm_context
    RubyLLM.context do |config|
      llm_provider.configure(config, credential_data["api_key"])
    end
  end

  def disable_credential_and_feeds(last_error: nil)
    with_lock do
      update!(state: :inactive, last_validated_at: Time.current, last_error: last_error)
      Event.create!(type: "ai_credential_deactivated", level: :warning,
                    subject: self, user: user)
      feeds.where(state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
    end
  end

  private

  def assign_name_if_blank
    return if display_name.present? || provider.blank?

    self.display_name = generate_unique_name
  end

  def generate_unique_name
    label = provider
    existing = self.class.where(user_id: user_id, provider: provider).pluck(:display_name).map(&:downcase).to_set
    CredentialNameGenerator.new(label, existing).generate.split.map(&:capitalize).join(" ")
  end

  def api_key_present
    return if provider.blank?

    errors.add(:base, "Enter your API key") if credential_data.blank? || credential_data["api_key"].blank?
  end

  # Detach this credential from every dependent feed. Enabled feeds reuse the
  # feed's generic disable-and-event transition; drafts and already-disabled
  # feeds keep their state and receive a removal-only event.
  def disable_dependent_feeds
    feeds.find_each do |feed|
      feed.update_column(:ai_credential_id, nil)
      next if feed.enabled? && feed.disable_with_event!(REMOVED_EVENT_TYPE, { disabled: true })

      Event.create!(
        type: REMOVED_EVENT_TYPE,
        level: :warning,
        subject: feed,
        user: user,
        metadata: { disabled: false }
      )
    end
  end
end
