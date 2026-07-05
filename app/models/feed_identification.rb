class FeedIdentification < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  def invalid_processing?
    processing? && started_at.nil?
  end

  # The candidate the chooser preselects and the new-feed form is built from: the
  # highest-ranked one that can fetch the source.
  def suggested_candidate
    attributes = working_candidates.first
    Candidate.new(attributes) if attributes
  end

  # Candidates that can fetch the source (spec §7): the count of these drives how
  # the result is presented. A candidate counts unless it's known-broken — tested
  # and failed, or unreachable — so in practice this is the passed set (detection
  # always records a verdict). Memoized: read a few times per request.
  def working_candidates
    @working_candidates ||= candidates.reject do |attributes|
      candidate = Candidate.new(attributes)
      candidate.failed? || candidate.unreachable?
    end
  end

  # How the detection result should present (spec §7):
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
