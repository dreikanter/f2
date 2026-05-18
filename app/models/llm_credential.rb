# A user's API credential for one AI provider. Mirrors the AccessToken
# lifecycle (pending → validating → active|inactive). `credential_data`
# stores provider-specific fields (e.g. `{ "api_key" => "..." }`) and is
# encrypted at rest.
class LlmCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80

  belongs_to :user
  # `dependent` is handled manually by `disable_dependent_feeds` so we can
  # both nullify the reference and pull any feed left enabled out of the
  # enabled state in one pass.
  has_many :feeds

  encrypts :credential_data

  enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

  validates :provider, presence: true, inclusion: { in: ->(_) { LlmProvider.all } }
  validates :display_name,
            presence: true,
            length: { maximum: DISPLAY_NAME_MAX_LENGTH },
            uniqueness: { scope: [:user_id, :provider] }

  validate :credential_data_matches_provider_schema

  before_save :clear_other_defaults_if_promoting
  before_destroy :disable_dependent_feeds

  scope :for_provider, ->(provider) { where(provider: provider) }

  def make_default!
    transaction do
      self.class.where(user_id: user_id, provider: provider).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  private

  def credential_data_matches_provider_schema
    return if provider.blank?
    return errors.add(:credential_data, "is missing") if credential_data.blank?

    schema = LlmProvider.credential_schema_for(provider)
    return if schema.blank?

    JSONSchemer.schema(schema).validate(credential_data).each do |error|
      pointer = error["data_pointer"].to_s
      message = pointer.empty? ? error["error"] : "#{pointer} #{error['error']}"
      errors.add(:credential_data, message)
    end
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
