require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "page_header without block renders title with simple layout" do
    result = page_header("Test Title")

    expected = <<~HTML.strip
      <div class="d-flex justify-content-between align-items-center mb-4"><h1>Test Title</h1></div>
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


  test "post_content_preview returns empty string for nil content" do
    assert_equal "", post_content_preview(nil)
  end

  test "post_content_preview returns empty string for blank content" do
    assert_equal "", post_content_preview("")
    assert_equal "", post_content_preview("   ")
  end

  test "post_content_preview truncates long content" do
    long_content = "a" * 200
    result = post_content_preview(long_content)
    assert result.length < 200
    assert result.end_with?("...")
  end

  test "post_content_preview returns content as-is when short" do
    short_content = "Short content"
    assert_equal short_content, post_content_preview(short_content)
  end

  test "post_content_preview strips whitespace" do
    content_with_whitespace = "  Content with spaces  "
    assert_equal "Content with spaces", post_content_preview(content_with_whitespace)
  end

  test "icon returns basic icon without classes" do
    result = icon("star")
    assert_equal '<i class="bi bi-star"></i>', result
  end

  test "icon returns icon with css class" do
    result = icon("star", css_class: "text-warning")
    assert_equal '<i class="bi bi-star text-warning"></i>', result
  end

  test "icon returns icon with title" do
    result = icon("star", title: "Favorite")
    assert_equal '<i class="bi bi-star" title="Favorite"></i>', result
  end

  test "icon returns icon with css class and title" do
    result = icon("check-circle", css_class: "text-success me-2", title: "Complete")
    assert_equal '<i class="bi bi-check-circle text-success me-2" title="Complete"></i>', result
  end

  test "post_status_icon returns draft icon for draft status" do
    result = post_status_icon("draft")
    expected = '<i class="bi bi-file-earmark text-muted" title="Draft"></i>'
    assert_equal expected, result
  end

  test "post_status_icon returns enqueued icon for enqueued status" do
    result = post_status_icon("enqueued")
    expected = '<i class="bi bi-clock text-secondary" title="Enqueued"></i>'
    assert_equal expected, result
  end

  test "post_status_icon returns rejected icon for rejected status" do
    result = post_status_icon("rejected")
    expected = '<i class="bi bi-x-circle text-danger" title="Rejected"></i>'
    assert_equal expected, result
  end

  test "post_status_icon returns published icon for published status" do
    result = post_status_icon("published")
    expected = '<i class="bi bi-check-circle-fill text-success" title="Published"></i>'
    assert_equal expected, result
  end

  test "post_status_icon returns failed icon for failed status" do
    result = post_status_icon("failed")
    expected = '<i class="bi bi-exclamation-triangle text-danger" title="Failed"></i>'
    assert_equal expected, result
  end

  test "post_status_icon returns capitalized text for unknown status" do
    result = post_status_icon("unknown")
    expected = '<span class="text-muted">Unknown</span>'
    assert_equal expected, result
  end

  test "highlight_json wraps output in highlight div" do
    json_hash = { "test" => "value" }
    result = highlight_json(json_hash)

    assert_includes result, "<div class=\"highlight\">"
    assert_includes result, "</div>"
  end
end
