class LlmChat < ApplicationRecord
  RETENTION = 7.days
  TERMINAL_STATUSES = %w[succeeded failed interrupted].freeze

  acts_as_chat message_class: "LlmMessage", messages_foreign_key: :llm_chat_id

  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :ai_credential, optional: true
  has_many :event_references, as: :reference, dependent: :delete_all

  enum :status, { running: 0, succeeded: 1, failed: 2, interrupted: 3 }, default: :running
  enum :purpose, { scheduled_run: 0, preview: 1 }

  validates :requested_provider, :requested_model, :profile_key, :purpose, :status,
            :started_at, :deadline_at, presence: true

  # Lifecycle fields are written only by finish!'s conditional update.
  attr_readonly :user_id, :requested_provider, :requested_model, :profile_key,
                :purpose, :started_at, :deadline_at, :status, :finished_at, :error_category

  scope :unexpired, -> { where("created_at > ?", RETENTION.ago) }
  scope :expired, -> { where(created_at: ..RETENTION.ago) }
  scope :overdue, -> { running.where(deadline_at: ..Time.current) }

  # @param status [Symbol, String] terminal extraction outcome
  # @param error_category [String, nil] classification without provider error text
  # @return [Boolean] whether this call won the terminal transition
  def finish!(status:, error_category: nil)
    status = status.to_s
    raise ArgumentError, "invalid terminal status: #{status}" unless TERMINAL_STATUSES.include?(status)

    now = Time.current
    pending = self.class.where(id: id, status: :running)
    pending = pending.where("deadline_at > ?", now) unless status == "interrupted"
    changed = pending.update_all(status: status, error_category: error_category, finished_at: now, updated_at: now)
    reload if changed == 1
    changed == 1
  end
end
