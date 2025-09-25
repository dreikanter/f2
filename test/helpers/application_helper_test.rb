require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "page_header without block renders title with simple layout" do
    result = page_header("Test Title")

    expected = <<~HTML.strip
      <div class="mb-4"><h1>Test Title</h1></div>
    HTML

    assert_equal expected, result
  end

  test "page_header with block renders title and content with flex layout" do
    result = page_header("Test Title") do
      content_tag(:a, "Link", href: "/test", class: "btn btn-primary")
    end

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Test Title</h1><a href="/test" class="btn btn-primary">Link</a></div>
    HTML

    assert_equal expected, result
  end

  test "page_header with text block content" do
    result = page_header("Settings") do
      "Some content"
    end

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Settings</h1>Some content</div>
    HTML

    assert_equal expected, result
  end
end
