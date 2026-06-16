class PostAttachmentsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def render?
    attachment_urls.present?
  end

  def attachment_urls
    @post.attachment_urls
  end

  def thumbnail_url(url)
    ImgproxyUrl.preview(url)
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
