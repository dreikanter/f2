class FeedEntry < ApplicationRecord
  belongs_to :feed

  validates :external_id, :title, presence: true
  validates :external_id, uniqueness: { scope: :feed_id }

  enum :status, { pending: 0, processed: 1, failed: 2 }
end
