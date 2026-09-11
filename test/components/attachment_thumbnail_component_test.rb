require "test_helper"

class AttachmentThumbnailComponentTest < ViewComponent::TestCase
  def render_thumbnail(**options)
    render_inline(AttachmentThumbnailComponent.new(url: "https://example.com/a.png", position: 1,
                                                   key: "preview.image-attachment", **options))
  end

  test "#render should link the original behind a lightbox target" do
    link = render_thumbnail.at_css('[data-key="preview.image-attachment"]')

    assert_equal "https://example.com/a.png", link["href"]
    assert_equal "Open image attachment 1", link["aria-label"]
    assert_equal "item", link["data-lightbox-target"]
  end

  test "#render should size the thumbnail through imgproxy" do
    image = render_thumbnail.at_css("img")

    assert_equal ImgproxyUrl.preview("https://example.com/a.png"), image["src"]
    assert_equal ImgproxyUrl::THUMBNAIL_SIZE.to_s, image["width"]
    assert_predicate image["srcset"], :present?
  end

  test "#render should leave the thumbnail undescribed by default" do
    assert_equal "", render_thumbnail.at_css("img")["alt"]
  end

  test "#render should use the given alt text" do
    assert_equal "a.png", render_thumbnail(alt: "a.png").at_css("img")["alt"]
  end
end
