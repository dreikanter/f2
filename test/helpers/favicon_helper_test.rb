require "test_helper"

class FaviconHelperTest < ActionView::TestCase
  test "#favicon_path should serve the standard icon in production" do
    assert_equal "/icon.png", favicon_path("png", "production")
    assert_equal "/icon.svg", favicon_path("svg", "production")
  end

  test "#favicon_path should serve the green icon outside production" do
    assert_equal "/icon-green.png", favicon_path("png", "staging")
    assert_equal "/icon-green.svg", favicon_path("svg", "development")
  end

  test "#favicon_path should default to the current environment" do
    assert_equal "/icon-green.png", favicon_path("png")
  end
end
