class Post < ApplicationRecord
  belongs_to :feed
  belongs_to :feed_entry

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }
  validates :published_at, presence: true
  validates :url, presence: true

  enum :status, { draft: 0, enqueued: 1, rejected: 2, published: 3, failed: 4 }
end
