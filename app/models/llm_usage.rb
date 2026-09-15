# Stored accounting for AI request attempts. Event details and feed summaries
# use these records to report outcomes, token counts, and estimated costs.
class LlmUsage < ApplicationRecord
  # Aggregate stats use a bounded window so recent usage remains useful even if
  # a retention policy is introduced later.
  STATS_PERIOD = 30.days

  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :ai_credential, optional: true

  scope :within_stats_period, -> { where(created_at: STATS_PERIOD.ago..) }
  scope :overdue, -> { pending.where(deadline_at: ..Time.current) }

  # No FK backs the polymorphic reference, so clean these up on destroy to
  # avoid dangling event_references.
  has_many :event_references, as: :reference, dependent: :delete_all

  enum :stage, { loader: 0, processor: 1, normalizer: 2 }
  enum :purpose, { scheduled_run: 0, preview: 1 }
  enum :outcome, {
    success: 0,
    schema_error: 1,
    provider_error: 2,
    rate_limited: 3,
    timeout: 4,
    pending: 5,
    interrupted: 6
  }

  validates :provider, presence: true
  validates :model, presence: true
  validates :outcome, presence: true
  validates :started_at, presence: true
  validates :finished_at, presence: true, unless: :unresolved?
  validates :deadline_at, presence: true, if: :unresolved?

  attr_readonly :user_id, :profile_key, :stage, :purpose, :provider, :model,
                :started_at, :deadline_at

  # @param chat [LlmChat] extraction metadata to snapshot before dispatch
  # @param event [Event] activity that owns this attempt's accounting
  # @param retrieval [Hash] retrieval mode and known cost coverage
  # @return [LlmUsage] pending attempt with its committed event reference
  def self.start!(chat:, event:, retrieval: {})
    transaction do
      create!(
        user: chat.user,
        feed: chat.feed,
        ai_credential: chat.ai_credential,
        profile_key: chat.profile_key,
        stage: :loader,
        purpose: chat.purpose,
        provider: chat.requested_provider,
        model: chat.requested_model,
        started_at: Time.current,
        deadline_at: chat.deadline_at,
        outcome: :pending,
        retrieval: retrieval
      ).tap { |usage| event.event_references.create!(reference: usage) }
    end
  end

  def unresolved?
    pending? || interrupted?
  end

  # A late observation resolves accounting without changing the extraction.
  # @return [Boolean] whether this observation settled the attempt
  def settle!(outcome:, finished_at: Time.current, input_tokens: nil, output_tokens: nil,
              cache_read_tokens: nil, cache_write_tokens: nil, thinking_tokens: nil,
              cost_estimate_cents: nil, retrieval: nil, error_message: nil)
    outcome = outcome.to_s
    unless self.class.outcomes.key?(outcome) && !%w[pending interrupted].include?(outcome)
      raise ArgumentError, "invalid settled outcome: #{outcome}"
    end

    with_lock do
      return false unless unresolved?

      update!(
        outcome: outcome,
        finished_at: finished_at,
        duration_ms: ((finished_at - started_at) * 1000).round,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cache_read_tokens: cache_read_tokens,
        cache_write_tokens: cache_write_tokens,
        thinking_tokens: thinking_tokens,
        cost_estimate_cents: cost_estimate_cents,
        retrieval: retrieval || self.retrieval,
        error_message: error_message
      )
    end
    true
  end

  # No finish time or token count is known when a worker disappears.
  # @return [Boolean] whether the pending attempt became interrupted
  def interrupt!
    with_lock do
      return false unless pending?

      update!(outcome: :interrupted)
    end
    true
  end
end
