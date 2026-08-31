require "test_helper"

class HtmlTextUtilsTest < ActiveSupport::TestCase
  class TestClass
    include HtmlTextUtils
  end

  def subject
    @subject ||= TestClass.new
  end

  test "#strip_html should remove HTML tags and normalize whitespace" do
    html = "<p>Hello   <strong>world</strong></p>"
    result = subject.strip_html(html)
    assert_equal "Hello world", result
  end

  test "#strip_html should return empty string for blank input" do
    assert_equal "", subject.strip_html(nil)
    assert_equal "", subject.strip_html("")
  end

  test "#strip_html_preserving_paragraphs should preserve plain-text paragraphs" do
    text = "First paragraph.\r\n\r\nSecond   paragraph.\nThird line."

    assert_equal "First paragraph.\n\nSecond paragraph.\nThird line.",
                 subject.strip_html_preserving_paragraphs(text)
  end

  test "#strip_html_preserving_paragraphs should translate HTML paragraphs and breaks" do
    html = "<p>Hello <strong>world</strong></p><p>Second<br>line</p>"

    assert_equal "Hello world\n\nSecond\nline", subject.strip_html_preserving_paragraphs(html)
  end

  test "#strip_html_preserving_paragraphs should return empty string for blank input" do
    assert_equal "", subject.strip_html_preserving_paragraphs(nil)
    assert_equal "", subject.strip_html_preserving_paragraphs("")
  end

  test "#extract_images should extract image sources" do
    html = '<p><img src="https://example.com/1.jpg"><img src="https://example.com/2.png"></p>'
    result = subject.extract_images(html)
    assert_equal ["https://example.com/1.jpg", "https://example.com/2.png"], result
  end

  test "#extract_images should skip images without src" do
    html = '<p><img alt="test"><img src="https://example.com/image.jpg"></p>'
    result = subject.extract_images(html)
    assert_equal ["https://example.com/image.jpg"], result
  end

  test "#extract_images should skip emoji images marked with a class" do
    html = <<~HTML
      <p>Surrounded <img src="https://s.w.org/images/core/emoji/16.0.1/72x72/1f414.png" alt="🐔" class="wp-smiley"></p>
      <p><img src="https://example.com/comic.jpg"></p>
    HTML

    assert_equal ["https://example.com/comic.jpg"], subject.extract_images(html)
  end

  test "#extract_images should skip emoji images without a class" do
    html = '<p><img src="https://s.w.org/images/core/emoji/16.0.1/72x72/1f414.png" alt="🐔"></p>'

    assert_equal [], subject.extract_images(html)
  end

  test "#extract_images should keep images with an unrelated class" do
    html = '<p><img src="https://example.com/comic.jpg" class="alignnone size-full"></p>'

    assert_equal ["https://example.com/comic.jpg"], subject.extract_images(html)
  end

  test "#extract_images should return empty array for blank input" do
    assert_equal [], subject.extract_images(nil)
    assert_equal [], subject.extract_images("")
  end

  test "#truncate_text should truncate long text" do
    long_text = "a" * 100
    result = subject.truncate_text(long_text, max_length: 50)
    assert result.length <= 50
    assert result.ends_with?("…")
  end

  test "#truncate_text should not truncate short text" do
    short_text = "Hello world"
    result = subject.truncate_text(short_text, max_length: 50)
    assert_equal "Hello world", result
  end

  test "#content_fit_limit should leave room for the separator and the URL" do
    limit = subject.content_fit_limit("https://example.com", max_content_length: 100)
    assert_equal 100 - HtmlTextUtils::CONTENT_URL_SEPARATOR.length - "https://example.com".length, limit
  end

  test "#content_fit_limit should return the full limit without a usable URL" do
    assert_equal 100, subject.content_fit_limit(nil, max_content_length: 100)
    assert_equal 100, subject.content_fit_limit("https://example.com", max_content_length: 100, max_url_length: 5)
  end

  test "#post_content_with_url should append the URL to the content" do
    result = subject.post_content_with_url("Hello", "https://example.com")
    assert_equal "Hello - https://example.com", result
  end

  test "#post_content_with_url should truncate the content to the fit limit" do
    url = "https://example.com"
    result = subject.post_content_with_url("a" * 100, url, max_content_length: 50)

    assert_equal 50, result.length
    assert result.ends_with?("…#{HtmlTextUtils::CONTENT_URL_SEPARATOR}#{url}")
  end

  test "#post_content_with_url should drop a URL longer than the limit" do
    result = subject.post_content_with_url("Hello", "https://example.com", max_url_length: 5)
    assert_equal "Hello", result
  end

  test "#post_content_with_url should return the URL alone for blank content" do
    assert_equal "https://example.com", subject.post_content_with_url("", "https://example.com")
    assert_equal "", subject.post_content_with_url("", "https://example.com", max_url_length: 5)
    assert_equal "", subject.post_content_with_url("", nil)
  end

  test "#post_content_with_url should truncate content without a URL" do
    result = subject.post_content_with_url("a" * 100, nil, max_content_length: 50)
    assert_equal 50, result.length
  end
end
