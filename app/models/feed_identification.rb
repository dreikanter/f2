class FeedIdentification < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  # Order the chooser prefers when preselecting a candidate: a proven one
  # first, then the untested AI fallback, then a reachable-but-untested source.
  # A `failed` candidate is never preselected — its radio is disabled.
  RECOMMENDED_TEST_STATUSES = %w[
    passed
    not_tested
    unreachable
  ].freeze

  def invalid_processing?
    processing? && started_at.nil?
  end

  # The candidate the chooser preselects and the new-feed form is built from.
  # Skips failed/unreachable toward a passed candidate, falling back to the AI
  # option when nothing structured worked.
  def recommended_candidate
    RECOMMENDED_TEST_STATUSES.each do |test_status|
      match = candidates.find { |candidate| candidate["test_status"] == test_status }
      return match if match
    end

    candidates.find { |candidate| candidate["test_status"] != "failed" } || candidates.first
  end
end
