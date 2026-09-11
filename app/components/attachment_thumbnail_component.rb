# One image attachment, sized through imgproxy and linked to the original so
# the lightbox can open it.
class AttachmentThumbnailComponent < ViewComponent::Base
  # @param url [String] the attachment's original URL
  # @param position [Integer] the attachment's 1-based place in its post
  # @param key [String] the link's test hook
  # @param alt [String] alt text for the thumbnail
  def initialize(url:, position:, key:, alt: "")
    @url = url
    @position = position
    @key = key
    @alt = alt
  end

  def call
    link_to url, target: "_blank", rel: "noopener",
            class: "block overflow-hidden rounded-md border border-border transition hover:border-ring",
            aria: { label: "Open image attachment #{position}" },
            data: { lightbox_target: "item", action: "click->lightbox#open", key: key } do
      image_tag ImgproxyUrl.preview(url), alt: alt, loading: "lazy", srcset: ImgproxyUrl.preview_srcset(url),
                width: ImgproxyUrl::THUMBNAIL_SIZE, height: ImgproxyUrl::THUMBNAIL_SIZE,
                class: "h-24 w-24 bg-surface-sunken object-cover"
    end
  end

  private

  attr_reader :url, :position, :key, :alt
end
