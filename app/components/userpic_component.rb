# FreeFeed userpic scaled through imgproxy, so browsers load avatars from our
# image proxy (which caches them) instead of hotlinking the FreeFeed media
# host. Falls back to the bundled placeholder when no picture URL is on record,
# e.g. for tokens validated before userpics were captured.
class UserpicComponent < ViewComponent::Base
  PLACEHOLDER = "default-userpic-75.png"

  def initialize(url:, alt: "", css_class: nil, data: {})
    @url = url
    @alt = alt
    @css_class = css_class
    @data = data
  end

  def call
    image_tag src,
      srcset: srcset,
      width: ImgproxyUrl::USERPIC_SIZE,
      height: ImgproxyUrl::USERPIC_SIZE,
      alt: @alt,
      class: @css_class,
      data: @data
  end

  private

  def src
    @url.present? ? ImgproxyUrl.userpic(@url) : PLACEHOLDER
  end

  def srcset
    ImgproxyUrl.userpic_srcset(@url) if @url.present?
  end
end
