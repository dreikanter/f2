class PostPublication < ApplicationRecord
  belongs_to :post

  validates :post_id, uniqueness: true
  validates :attachments_processed_count, :comments_published_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
