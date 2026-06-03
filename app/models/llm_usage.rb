# Append-only audit row for one LLM API call. Written by LlmClient
# regardless of outcome so users see the true cost of AI features
# including failed calls.
class LlmUsage < ApplicationRecord
  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :llm_credential, optional: true

  enum :stage, { loader: 0, processor: 1, normalizer: 2 }
  enum :purpose, { scheduled_run: 0, preview: 1, credential_validation: 2 } # credential_validation no longer written; kept for existing rows
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
