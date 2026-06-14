class FeedIdentification < ApplicationRecord
  # Server gives up identifying a feed after this many seconds.
  TIMEOUT = 30.seconds

  # Poll a couple of cycles past the server-side timeout so a request lands
  # inside the timed_out? window and renders the friendly error. Matching the
  # timeout exactly lets the client hit its poll cap first and freeze the
  # spinner with no message.
  POLLING_MAX_POLLS = (TIMEOUT.in_milliseconds / StatePolling::POLLING_INTERVAL_MS) + 2

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
