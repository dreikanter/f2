# Stores a user's API credential for a web search provider.
class SearchCredential < ApplicationRecord
  DISPLAY_NAME_MAX_LENGTH = 80

  belongs_to :user
  has_many :feeds

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

  # One debug event per search API call — the accounting record behind the
  # per-credential usage stats and the refresh event's search-call count
  # (spec 006 §6). feed_id lives in metadata rather than a reference so the
  # refresh workflow can window this credential's calls to one feed's run.
  def record_search_call(purpose:, outcome:, feed: nil, error: nil)
    Event.create!(
      type: "web_search",
      level: :debug,
      subject: self,
      user: user,
      metadata: {
        provider: provider,
        purpose: purpose.to_s,
        outcome: outcome.to_s,
        feed_id: feed&.id,
        error: error
      }.compact
    )
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

  def disable_dependent_feeds
    affected_feed_ids = feeds.pluck(:id)
    return if affected_feed_ids.empty?

    Feed.where(id: affected_feed_ids).update_all(search_credential_id: nil)
    Feed.where(id: affected_feed_ids, state: Feed.states[:enabled]).update_all(state: Feed.states[:disabled])
  end
end
