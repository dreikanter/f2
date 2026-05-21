class FeedDetail < ApplicationRecord
  IDENTIFICATION_TIMEOUT_SECONDS = 30

  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :url, presence: true

  def invalid_processing?
    processing? && started_at.nil?
  end

  def timed_out?
    processing? && started_at.present? && started_at < IDENTIFICATION_TIMEOUT_SECONDS.seconds.ago
  end
end
