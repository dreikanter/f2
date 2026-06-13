# A user's API credential for one AI provider. Mirrors the AccessToken
# lifecycle (pending → validating → active|inactive). `credential_data`
# stores provider-specific fields (e.g. `{ "api_key" => "..." }`) and is
# encrypted at rest.
class LlmCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80
  VALIDATION_POLLING_INTERVAL_MS = 2000
  VALIDATION_POLLING_MAX_POLLS = 35

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
  before_save :clear_other_defaults_if_promoting
  before_destroy :disable_dependent_feeds

  scope :for_provider, ->(provider) { where(provider: provider) }

  def make_default!
    transaction do
      self.class.where(user_id: user_id, provider: provider).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  def ruby_llm_context
    RubyLLM.context do |config|
      config.public_send("#{provider}_api_key=", credential_data["api_key"])
    end
  end

  def disable_credential_and_feeds(last_error: nil)
    with_lock do
      update!(state: :inactive, last_validated_at: Time.current, last_error: last_error)
      Event.create!(type: "llm_credential_deactivated", level: :warning,
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

  def clear_other_defaults_if_promoting
    return unless is_default? && (will_save_change_to_is_default? || new_record?)

    self.class
      .where(user_id: user_id, provider: provider)
      .where.not(id: id)
      .update_all(is_default: false)
  end

  # Mirrors AccessToken#disable_associated_feeds: drop the credential
  # reference and pull any feed left without a usable credential out of
  # the enabled state. The feeds.user_id is already set, so we don't
  # have to touch other ownership fields.
  def disable_dependent_feeds
    affected_feed_ids = feeds.pluck(:id)
    return if affected_feed_ids.empty?

    Feed.where(id: affected_feed_ids).update_all(llm_credential_id: nil)
    Feed.where(id: affected_feed_ids, state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
  end
end
