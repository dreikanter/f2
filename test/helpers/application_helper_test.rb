require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "page_header without block renders title with simple layout" do
    result = page_header("Test Title")

    assert_includes result, '<div class="mb-4">'
    assert_includes result, '<h1>Test Title</h1>'
    assert_not_includes result, "d-flex"
  end

  test "page_header with block renders title and content with flex layout" do
    result = page_header("Test Title") do
      content_tag(:a, "Link", href: "/test", class: "btn btn-primary")
    end

    assert_includes result, '<div class="d-flex justify-content-between align-items-center mb-4">'
    assert_includes result, '<h1>Test Title</h1>'
    assert_includes result, 'href="/test"'
    assert_includes result, 'class="btn btn-primary"'
    assert_includes result, '>Link</a>'
  end

  test "page_header with text block content" do
    result = page_header("Settings") do
      "Some content"
    end

    assert_includes result, '<h1>Settings</h1>'
    assert_includes result, "Some content"
    assert_includes result, "d-flex justify-content-between"
  end
end