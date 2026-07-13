# Append-only audit row for one LLM API call. Written by LlmClient
# regardless of outcome so users see the true cost of AI features
# including failed calls.
class LlmUsage < ApplicationRecord
  # Usage rows are subject to retention pruning, so aggregate stats in the UI
  # must cover a bounded window rather than all time — all-time totals would
  # silently shrink as old rows expire.
  STATS_PERIOD = 30.days

  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :ai_credential, optional: true

  scope :within_stats_period, -> { where(created_at: STATS_PERIOD.ago..) }

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
    timeout: 4
  }

  validates :provider, presence: true
  validates :model, presence: true
  validates :outcome, presence: true
  validates :started_at, :finished_at, presence: true
end
