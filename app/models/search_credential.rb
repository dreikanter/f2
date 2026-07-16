# Stores a user's API credential for a web search provider.
class SearchCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80
  REMOVED_EVENT_TYPE = "feed_search_credential_removed"

  belongs_to :user
  has_many :feeds
  has_many :events, as: :subject, dependent: :destroy

  encrypts :credential_data

  enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

  validates :provider, presence: true, inclusion: { in: ->(_) { WebSearchProvider::REGISTRY.keys } }

  validates :display_name,
            presence: true,
            length: { maximum: DISPLAY_NAME_MAX_LENGTH },
            uniqueness: { scope: [:user_id, :provider] }

  validate :api_key_present

  before_validation :assign_name_if_blank, on: :create
  before_destroy :disable_dependent_feeds

  def default?
    user.default_search_credential_id == id
  end

  def make_default!
    user.update!(default_search_credential: self)
  end

  def web_search_provider
    WebSearchProvider.for(provider, api_key: credential_data["api_key"])
  end

  def provider_label
    WebSearchProvider.label_for(provider)
  end

  def estimated_search_cost_cents(call_count)
    BigDecimal(WebSearchProvider.cents_per_1k_requests_for(provider).to_s) * call_count / 1000
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

      feeds.where(state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
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

  # Detach this credential from every dependent feed. Enabled feeds reuse the
  # feed's generic disable-and-event transition; drafts and already-disabled
  # feeds keep their state and receive a removal-only event.
  def disable_dependent_feeds
    feeds.find_each do |feed|
      feed.update_column(:search_credential_id, nil)
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
