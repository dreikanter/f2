class Post < ApplicationRecord
  # Freefeed Server length limits
  MAX_CONTENT_LENGTH = 3000 # graphemes
  MAX_COMMENT_LENGTH = 3000 # characters

  NORMALIZED_ATTRIBUTES = [
    :uid,
    :published_at,
    :source_url,
    :content,
    :attachment_urls,
    :comments,
    :status,
    :validation_errors
  ].freeze

  belongs_to :feed
  belongs_to :feed_entry

  validates :uid, presence: true
  validates :uid, uniqueness: { scope: :feed_id }
  validates :published_at, presence: true
  validates :source_url, presence: true
  validates :content, length: { maximum: MAX_CONTENT_LENGTH }

  validate :validate_comments_length

  enum :status, {
    draft: 0,
    enqueued: 1,
    rejected: 2,
    published: 3,
    failed: 4
  }

  def normalized_attributes
    as_json(only: NORMALIZED_ATTRIBUTES)
  end

  private

  def validate_comments_length
    return unless comments.is_a?(Array)

    comments.each_with_index do |comment, index|
      next unless comment.is_a?(String) && comment.length > MAX_COMMENT_LENGTH

      errors.add(:comments, "Comment #{index + 1} exceeds maximum length of #{MAX_COMMENT_LENGTH} characters")
    end
  end
end
