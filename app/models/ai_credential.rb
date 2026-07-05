# A user's API credential for one AI provider. Mirrors the AccessToken
# lifecycle (pending → validating → active|inactive). `credential_data`
# stores provider-specific fields (e.g. `{ "api_key" => "..." }`) and is
# encrypted at rest.
class AiCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80

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

  scope :for_provider, ->(provider) { where(provider: provider) }

  def default?
    user.default_ai_credential_id == id
  end

  def make_default!
    user.update!(default_ai_credential: self)
  end

  def offers_model?(model_id)
    return false if model_id.blank?

    available_models.any? { |model| model["id"] == model_id }
  end

  def ruby_llm_context
    RubyLLM.context do |config|
      LlmProvider.find(provider).configure(config, credential_data["api_key"])
    end
  end

  def disable_credential_and_feeds(last_error: nil)
    with_lock do
      update!(state: :inactive, last_validated_at: Time.current, last_error: last_error)
      Event.create!(type: "ai_credential_deactivated", level: :warning,
                    subject: self, user: user, message: "")
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
    NameGenerator.new(label, existing).generate.split.map(&:capitalize).join(" ")
  end

  def api_key_present
    return if provider.blank?

    errors.add(:base, "Enter your API key") if credential_data.blank? || credential_data["api_key"].blank?
  end

  # Mirrors AccessToken#disable_associated_feeds: drop the credential
  # reference and pull any feed left without a usable credential out of
  # the enabled state. The feeds.user_id is already set, so we don't
  # have to touch other ownership fields.
  def disable_dependent_feeds
    affected_feed_ids = feeds.pluck(:id)
    return if affected_feed_ids.empty?

    Feed.where(id: affected_feed_ids).update_all(ai_credential_id: nil)
    Feed.where(id: affected_feed_ids, state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
  end
end
