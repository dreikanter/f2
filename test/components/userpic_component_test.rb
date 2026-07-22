require "test_helper"
require "view_component/test_case"

class UserpicComponentTest < ViewComponent::TestCase
  USERPIC_URL = "https://media.freefeed.net/profilepics/testuser_75.jpg".freeze

  test "#render should show the userpic with a HiDPI srcset when a url is given" do
    result = render_inline(UserpicComponent.new(url: USERPIC_URL, alt: "testuser"))

    img = result.css("img").first
    assert_equal ImgproxyUrl.userpic(USERPIC_URL), img["src"]
    assert_equal ImgproxyUrl.userpic_srcset(USERPIC_URL), img["srcset"]
    assert_equal "testuser", img["alt"]
    assert_equal ImgproxyUrl::USERPIC_SIZE.to_s, img["width"]
    assert_equal ImgproxyUrl::USERPIC_SIZE.to_s, img["height"]
  end

  test "#render should fall back to the placeholder without a url" do
    result = render_inline(UserpicComponent.new(url: nil))

    img = result.css("img").first
    assert_includes img["src"], "default-userpic-75"
    assert_nil img["srcset"]
  end

  test "#render should pass through css class and data attributes" do
    result = render_inline(UserpicComponent.new(url: nil, css_class: "size-12", data: { key: "userpic" }))

    img = result.css("img").first
    assert_equal "size-12", img["class"]
    assert_equal "userpic", img["data-key"]
  end
end
