class OperationRun < ApplicationRecord
  ACTIVE_STATUSES = %i[queued running].freeze
  TERMINAL_STATUSES = %i[succeeded failed timed_out].freeze

  belongs_to :subject, polymorphic: true

  enum :kind, {
    validation: 0,
    groups_refresh: 1
  }

  enum :status, {
    queued: 0,
    running: 1,
    succeeded: 2,
    failed: 3,
    timed_out: 4,
    superseded: 5
  }

  validates :kind, :status, presence: true

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  # @param subject [ApplicationRecord] record being processed
  # @param kind [Symbol, String] operation type
  # @param status [Symbol, String] initial status
  # @param timeout [ActiveSupport::Duration, Numeric, nil] timeout from start
  # @param context [Hash] immutable launch context
  # @return [OperationRun] new current run
  def self.start!(subject:, kind:, status: :running, timeout: nil, context: {})
    initial_status = status.to_s.to_sym
    raise ArgumentError, "invalid initial status: #{status}" unless initial_status.in?(ACTIVE_STATUSES)

    now = Time.current

    subject.with_lock do
      where(subject: subject, kind: kind).active.update_all(
        status: statuses[:superseded],
        finished_at: now,
        updated_at: now
      )

      create!(
        subject: subject,
        kind: kind,
        status: initial_status,
        started_at: initial_status == :running ? now : nil,
        deadline_at: initial_status == :running && timeout ? now + timeout : nil,
        context: context
      ).tap { |run| yield(subject, run) if block_given? }
    end
  end

  # Claims a queued run and keeps an already-running run usable by its worker.
  # @param timeout [ActiveSupport::Duration, Numeric] timeout from claim
  # @return [Boolean] whether this run remains current
  def claim!(timeout:)
    with_subject_lock do
      return false unless queued? || running?

      if queued?
        now = Time.current
        update!(status: :running, started_at: now, deadline_at: now + timeout)
        yield subject, deadline_at if block_given?
      end
    end

    true
  end

  # @param terminal_status [Symbol, String] successful or unsuccessful outcome
  # @return [Boolean] whether this run won the terminal transition
  def settle!(terminal_status)
    terminal_status = terminal_status.to_s.to_sym
    raise ArgumentError, "invalid terminal status: #{terminal_status}" unless terminal_status.in?(TERMINAL_STATUSES)

    with_subject_lock do
      return false unless queued? || running?

      yield subject if block_given?
      update!(status: terminal_status, finished_at: Time.current)
    end

    true
  end

  # @return [Boolean] whether the run completed successfully
  def succeed!(&)
    settle!(:succeeded, &)
  end

  # @return [Boolean] whether the run completed unsuccessfully
  def fail!(&)
    settle!(:failed, &)
  end

  # @return [Boolean] whether the run timed out
  def timeout!(&)
    settle!(:timed_out, &)
  end

  # @param stale_after [ActiveSupport::Duration, nil] fallback age for lost timeouts
  # @return [Boolean] whether polling should continue
  def in_progress?(stale_after: nil)
    return false unless queued? || running?
    return true unless stale_after

    (started_at || created_at) > stale_after.ago
  end

  private

  def with_subject_lock
    transaction do
      subject.with_lock do
        lock!
        yield
      end
    end
  end
end
