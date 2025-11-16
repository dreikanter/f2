class FeedDetail < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :url, presence: true

  # Find or create a feed detail record for a user and URL
  def self.find_or_initialize_for(user:, url:)
    find_or_initialize_by(user: user, url: url)
  end

  # Clean up old feed detail records
  scope :stale, -> { where("created_at < ?", 1.hour.ago) }
end
