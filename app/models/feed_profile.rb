class FeedProfile < ApplicationRecord
  belongs_to :user
  has_many :feeds, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  before_destroy :deactivate_related_feeds

  private

  def deactivate_related_feeds
    feeds.enabled.update_all(state: :disabled)
  end
end
