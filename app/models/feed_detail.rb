class FeedDetail < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :url, presence: true

  scope :stale, -> { where("created_at < ?", 1.hour.ago) }
end
