class FeedProfile < ApplicationRecord
  belongs_to :user
  has_many :feeds, dependent: :nullify
  has_many :feed_previews, dependent: :destroy

  validates :name, presence: true, uniqueness: true,
            length: { maximum: 100 },
            format: { with: /\A[a-z\d\-_]+\z/, message: "must contain only lowercase letters, numbers, hyphens, and underscores" }
  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  normalizes :name, with: ->(name) { name.to_s.strip.downcase }

  before_destroy :deactivate_related_feeds

  # Resolves and returns the loader class for this profile
  # @return [Class] the loader class
  def loader_class
    ClassResolver.resolve("Loader", loader)
  end

  # Resolves and returns the processor class for this profile
  # @return [Class] the processor class
  def processor_class
    ClassResolver.resolve("Processor", processor)
  end

  # Resolves and returns the normalizer class for this profile
  # @return [Class] the normalizer class
  def normalizer_class
    ClassResolver.resolve("Normalizer", normalizer)
  end

  private

  def deactivate_related_feeds
    feeds.enabled.update_all(state: :disabled)
  end
end
