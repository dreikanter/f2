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

  test "#extract_images should return empty array for blank input" do
    assert_equal [], subject.extract_images(nil)
    assert_equal [], subject.extract_images("")
  end

  test "#truncate_text should truncate long text" do
    long_text = "a" * 100
    result = subject.truncate_text(long_text, max_length: 50)
    assert result.length <= 50
    assert result.ends_with?("...")
  end

  test "#truncate_text should not truncate short text" do
    short_text = "Hello world"
    result = subject.truncate_text(short_text, max_length: 50)
    assert_equal "Hello world", result
  end
end
