class FeedEntry < ApplicationRecord
  belongs_to :feed

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }

  enum :status, { pending: 0, processed: 1, failed: 2 }
end
