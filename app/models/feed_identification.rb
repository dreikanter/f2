class FeedIdentification < ApplicationRecord
  POLLING_INTERVAL_MS = 2500
  TIMEOUT_AFTER = 85.seconds

  belongs_to :user

  # The detection lifecycle: processing is in-flight; the rest are settled
  # results written by FeedIdentificationFetcher.
  #   working: at least one candidate read the source (the feed form)
  #   unreachable: nothing connected, transient (the retry state)
  #   no_feed: reachable but nothing usable, terminal (the AI bridge)
  #   timed_out: the run exceeded its background deadline (the retry state)
  #
  # The integers are persisted, so a new state appends; reordering these
  # would silently reinterpret every existing row.
  enum :status, { processing: 0, working: 1, unreachable: 2, no_feed: 3, timed_out: 4 }

  validates :input, presence: true

  def invalid_processing?
    processing? && (started_at.nil? || run_id.blank?)
  end

  # Reset the row to a fresh in-flight detection. Shared by the creation entry
  # and the edit-source re-detection so both clear stale candidates and
  # schedule the run the same way.
  #
  # Two concurrent submits can both look the row up before either inserts; the
  # loser's insert then hits the user+input unique index. Returns false in that
  # case — the winner's detection is already in flight, so the stale copy
  # should be discarded — and true when this call (re)started detection.
  def restart_detection
    started_at = Time.current
    run_id = SecureRandom.uuid
    begin
      update!(status: :processing, started_at: started_at, candidates: [], run_id: run_id)
    rescue ActiveRecord::RecordNotUnique
      return false
    end

    FeedIdentificationJob.perform_later(id, run_id)
    FeedIdentificationTimeoutJob.set(wait_until: started_at + TIMEOUT_AFTER).perform_later(id, run_id)
    true
  end

  # @param status [Symbol] settled detection status
  # @param candidates [Array<Hash>] detected candidates
  # @param run_id [String] run token captured by the worker
  # @return [Boolean] whether the matching run was settled
  def settle_detection(status:, candidates:, run_id:)
    self.class.where(id: id, status: :processing, run_id: run_id)
              .update_all(status: status, candidates: candidates, updated_at: Time.current)
              .positive?
  end

  # @param run_id [String] run token captured by the timeout job
  # @return [FeedIdentification] self
  def timeout!(run_id:)
    updated = self.class.where(id: id, status: :processing, run_id: run_id)
                        .update_all(status: :timed_out, run_id: SecureRandom.uuid, updated_at: Time.current)
    reload if updated.positive?
    self
  end

  def self.polling_max_polls
    # The first poll is immediate. Two extra polls leave one interval for Solid
    # Queue to dispatch a due timeout and let the final poll render its result.
    TIMEOUT_AFTER.in_milliseconds.div(POLLING_INTERVAL_MS) + 2
  end

  # The candidate the chooser preselects and the new-feed form is built from: the
  # highest-ranked one that can fetch the source.
  def suggested_candidate
    working_candidates.first
  end

  # Candidates that can fetch the source. A candidate counts unless it's
  # known-broken (tested and failed, or unreachable), so in practice this is
  # the passed set: detection always records a verdict.
  def working_candidates
    candidates.map { Candidate.new(_1) }.reject do |candidate|
      candidate.failed? || candidate.unreachable?
    end
  end

  # Profile keys of the working candidates, in rank order. An edit's confirming
  # save only applies a source when the submitted profile is one of
  # these — a settled, source-reading candidate.
  def working_candidate_profile_keys
    working_candidates.map(&:profile_key)
  end

  # The URL the profile's working candidate actually reads: the discovered
  # feed URL when there is one, otherwise the input. Feeds anchor to this.
  def source_url_for(profile_key)
    candidate = working_candidates.find { |c| c.profile_key == profile_key }
    candidate&.resolved_url || input
  end

  # The settled identification a confirming save can trust for this URL:
  # the row keyed by the URL when it works, else the page identification
  # whose working candidate resolved to it.
  def self.working_for_source(user:, url:)
    return nil if url.blank?

    direct = find_by(user: user, input: url)
    return direct if direct&.working?

    resolved_to(user, url)
  end

  # Retire the rows behind a created feed's source: the row keyed by the
  # URL and the page identification that resolved to it. Either could
  # confirm a later edit, so neither may outlive its use.
  def self.cleanup_for_source(user:, url:)
    return if url.blank?

    [find_by(user: user, input: url), resolved_to(user, url)].compact.each(&:destroy)
  end

  def self.resolved_to(user, url)
    where(user: user, status: :working).detect do |identification|
      identification.working_candidates.any? { |c| c.resolved_url == url }
    end
  end
  private_class_method :resolved_to
end
