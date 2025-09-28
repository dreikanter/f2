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

  test "short_time_ago returns nil for nil input" do
    assert_nil short_time_ago(nil)
  end

  test "short_time_ago returns seconds for recent time" do
    time = 30.seconds.ago
    assert_equal "30s", short_time_ago(time)
  end

  test "short_time_ago returns minutes for time within hour" do
    time = 15.minutes.ago
    assert_equal "15m", short_time_ago(time)
  end

  test "short_time_ago returns hours for time within day" do
    time = 5.hours.ago
    assert_equal "5h", short_time_ago(time)
  end

  test "short_time_ago returns days for time within month" do
    time = 10.days.ago
    assert_equal "10d", short_time_ago(time)
  end

  test "short_time_ago returns months for time within year" do
    time = 3.months.ago
    assert_equal "3mo", short_time_ago(time)
  end

  test "short_time_ago returns years for old time" do
    time = 2.years.ago
    assert_equal "2y", short_time_ago(time)
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
end
