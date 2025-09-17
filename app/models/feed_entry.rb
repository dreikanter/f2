class FeedEntry < ApplicationRecord
  belongs_to :feed
  has_many :posts, dependent: :destroy

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }

  enum :status, { pending: 0, processed: 1 }
end
