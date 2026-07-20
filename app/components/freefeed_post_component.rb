class FreefeedPostComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  private

  attr_reader :post

  def feed
    post.feed
  end

  def author_name
    token = feed.access_token
    token&.owner.presence ||
      token&.access_token_detail&.user_info&.dig("username").presence ||
      "You"
  end

  def group_name
    feed.target_group
  end

  def group_url
    feed.target_group_url
  end

  def freefeed_url
    post.freefeed_url
  end

  def timestamp_tag
    time = post.published_at
    phrase = helpers.time_ago(time)

    helpers.content_tag(
      :time,
      phrase ? "#{phrase} ago" : "just now",
      datetime: time.rfc3339,
      title: helpers.long_time_format(time)
    )
  end

  def attachment_urls
    post.attachment_urls
  end

  def comments
    post.comments
  end

  def thumbnail_url(url)
    ImgproxyUrl.preview(url)
  end

  def thumbnail_srcset(url)
    ImgproxyUrl.preview_srcset(url)
  end

  def thumbnail_size
    ImgproxyUrl::THUMBNAIL_SIZE
  end

  def extract_filename(url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)
    filename.presence || "Attachment"
  rescue URI::InvalidURIError
    "Attachment"
  end
end
