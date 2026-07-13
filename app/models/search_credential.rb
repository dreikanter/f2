# Stores a user's API credential for a web search provider.
class SearchCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80

  belongs_to :user

  encrypts :credential_data

  enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

  validates :provider, presence: true, inclusion: { in: ->(_) { WebSearchProvider::REGISTRY.keys } }

  validates :display_name,
            presence: true,
            length: { maximum: DISPLAY_NAME_MAX_LENGTH },
            uniqueness: { scope: [:user_id, :provider] }

  validate :api_key_present

  before_validation :assign_name_if_blank, on: :create

  def default?
    user.default_search_credential_id == id
  end

  def make_default!
    user.update!(default_search_credential: self)
  end

  def web_search_provider
    WebSearchProvider.for(provider, api_key: credential_data["api_key"])
  end

  def deactivate!(last_error: nil)
    with_lock do
      update!(
        state: :inactive,
        last_validated_at: Time.current,
        last_error: last_error
      )

      Event.create!(
        type: "search_credential_deactivated",
        level: :warning,
        subject: self,
        user: user
      )
    end
  end

  private

  def assign_name_if_blank
    return if display_name.present? || provider.blank?

    self.display_name = generate_unique_name
  end

  def generate_unique_name
    existing = self.class.where(user_id: user_id, provider: provider).pluck(:display_name).map(&:downcase).to_set
    CredentialNameGenerator.new(provider, existing).generate.split.map(&:capitalize).join(" ")
  end

  def api_key_present
    return if provider.blank?

    errors.add(:base, "Enter your API key") if credential_data.blank? || credential_data["api_key"].blank?
  end
end
