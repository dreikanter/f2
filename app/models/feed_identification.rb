class FeedIdentification < ApplicationRecord
  # Server gives up identifying a feed after this many seconds.
  TIMEOUT = 30.seconds

  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  def invalid_processing?
    processing? && started_at.nil?
  end

  def timed_out?
    processing? && started_at.present? && started_at < TIMEOUT.ago
  end
end
