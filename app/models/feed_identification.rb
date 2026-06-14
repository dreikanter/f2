class FeedIdentification < ApplicationRecord
  belongs_to :user

  enum :status, { processing: 0, success: 1, failed: 2 }

  validates :input, presence: true

  # Build the feed the expanded form should pre-fill from the top-ranked
  # candidate. The user's input is written under the profile's input_shape
  # (url/query/…) so derived params never leak into feed identity.
  def build_recommended_feed(user)
    recommended = candidates.first || {}
    profile_key = recommended["profile_key"]
    input_shape = FeedProfile[profile_key]&.dig(:input_shape) || :url

    user.feeds.build(
      params: { input_shape.to_s => input },
      feed_profile_key: profile_key,
      name: recommended["title"]
    )
  end
end
