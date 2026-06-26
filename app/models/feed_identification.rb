class FeedIdentification < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  def invalid_processing?
    processing? && started_at.nil?
  end

  # The candidate the chooser preselects and the new-feed form is built from.
  def suggested_candidate
    detected_candidates.find(&:passed?) || detected_candidates.find(&:not_tested?) ||
      detected_candidates.find(&:unreachable?) || detected_candidates.reject(&:failed?).first ||
      detected_candidates.first
  end

  private

  # Lazy so the suggestion chain stops wrapping at the first match; memoized
  # so the repeated lookups share one enumerator.
  def detected_candidates
    @detected_candidates ||= candidates.lazy.map { |attributes| Candidate.new(attributes) }
  end
end
