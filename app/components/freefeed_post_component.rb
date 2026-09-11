class FreefeedPostComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  private

  attr_reader :post

  def feed
    post.feed
  end

  def token
    feed.access_token
  end

  def author_name
    token&.owner.presence ||
      token&.access_token_detail&.freefeed_user_info&.dig("username").presence ||
      "You"
  end

  def userpic_url
    token&.access_token_detail&.freefeed_user_info&.dig("profile_picture_url")
  end

  def group_name
    feed.target_group
  end

  def group_url
    feed.target_group_url
  end

  def freefeed_url
    post.freefeed_post_url
  end

  # FreeFeed spells the age out, so the preview does too.
  def timestamp_tag
    helpers.time_ago_phrase_tag(post.published_at)
  end

  def attachment_urls
    post.attachment_urls
  end

  def comments
    post.comments
  end

  def extract_filename(url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)
    filename.presence || "Attachment"
  rescue URI::InvalidURIError
    "Attachment"
  end
end
