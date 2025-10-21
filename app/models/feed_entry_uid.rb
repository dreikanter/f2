class FeedEntryUid < ApplicationRecord
  belongs_to :feed

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }
  validates :imported_at, presence: true
end
