class FeedIdentification < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  def invalid_processing?
    processing? && started_at.nil?
  end

  # Reset the row to a fresh in-flight detection. Shared by the creation entry
  # and the edit-source re-detection so both clear stale candidates/errors the
  # same way; the caller enqueues FeedIdentificationJob.
  #
  # Two concurrent submits can both look the row up before either inserts; the
  # loser's insert then hits the user+input unique index. Returns false in that
  # case — the winner's detection is already in flight, so the stale copy
  # should be discarded — and true when this call (re)started detection.
  def restart_detection!
    update!(status: :processing, started_at: Time.current, candidates: [], error: nil)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # The candidate the chooser preselects and the new-feed form is built from: the
  # highest-ranked one that can fetch the source.
  def suggested_candidate
    working_candidates.first
  end

  # Candidates that can fetch the source: the count of these drives how
  # the result is presented. A candidate counts unless it's known-broken — tested
  # and failed, or unreachable — so in practice this is the passed set (detection
  # always records a verdict).
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
    return direct if direct&.success? && direct.outcome == :working

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
    where(user: user, status: :success).detect do |identification|
      identification.working_candidates.any? { |c| c.resolved_url == url }
    end
  end
  private_class_method :resolved_to

  # How the detection result should present:
  #   :working     — at least one candidate read the source → the feed form
  #   :unreachable — nothing connected (couldn't-reach) → the transient retry state
  #   :no_feed     — reachable, but no candidate yields a feed → the terminal
  #                  error that offers the AI bridge
  def outcome
    return :working if working_candidates.any?
    return :unreachable if unreachable_only?

    :no_feed
  end

  private

  # Nothing was reachable to judge: the initial fetch never connected, or every
  # detected candidate failed on the network.
  def unreachable_only?
    return true if error == "unreachable"

    candidates.present? && candidates.all? { |attributes| Candidate.new(attributes).unreachable? }
  end
end
