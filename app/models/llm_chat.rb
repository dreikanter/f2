class LlmChat < ApplicationRecord
  RETENTION = 2.months
  TIMEOUT = 180.seconds
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

  before_validation :limit_deadline, on: :create
  after_create_commit :schedule_timeout, if: :running?

  # Lifecycle fields are written only by finish!'s conditional update.
  attr_readonly :user_id, :requested_provider, :requested_model, :profile_key,
                :purpose, :started_at, :deadline_at, :status, :finished_at, :error_category

  scope :unexpired, -> { where("created_at > ?", RETENTION.ago) }
  scope :expired, -> { where(created_at: ..RETENTION.ago) }
  scope :overdue, -> { running.where(deadline_at: ..Time.current) }

  # Run the prepared chat, leaving success to the processor's output validation.
  # @param provider [LlmProvider::Base] provider responsible for request configuration
  # @return [RubyLLM::Message] final SDK response
  def execute(provider:, execution_limits: {})
    raise ArgumentError, "Chat must be running" unless self.class.running.exists?(id)

    LlmExecution.new(chat: to_llm, provider: provider, deadline_at: deadline_at, **execution_limits).call
  ensure
    timeout!
  end

  # Settle expired work from either its worker or its timeout job.
  # @return [Boolean] whether this call interrupted an overdue chat
  def timeout!
    return false if deadline_at > Time.current

    finish!(status: :interrupted, error_category: "deadline_exceeded")
  end

  # @return [Boolean] whether validated output completed while the chat was active
  def complete!
    return true if finish!(status: :succeeded)

    timeout!
    false
  end

  # @param error [Exception] extraction failure to classify without storing its message
  # @return [Boolean] whether this call marked the chat failed
  def fail!(error)
    timeout!
    finish!(status: :failed, error_category: error.class.name)
  end

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

  private

  def limit_deadline
    return unless started_at && deadline_at

    self.deadline_at = [deadline_at, started_at + TIMEOUT].min
  end

  def schedule_timeout
    LlmChatTimeoutJob.set(wait_until: deadline_at).perform_later(id)
  end
end
