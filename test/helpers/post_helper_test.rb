require "test_helper"

class PostHelperTest < ActionView::TestCase
  include PostHelper
  include TimeHelper

  test "#post_metadata_segments should include feed link when requested" do
    feed = create(:feed, target_group: "testgroup")

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source",
      freefeed_post_id: "post-123"
    )

    segments = post_metadata_segments(post, show_feed: true, withdraw_allowed: false)

    assert_includes segments.first, feed.name
  end

  test "#post_metadata_segments should build default segments" do
    feed = create(:feed)

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source"
    )

    segments = post_metadata_segments(post, withdraw_allowed: false)

    assert_includes segments, "Attachments: #{post.attachment_urls.size}"
    assert_includes segments, "Comments: #{post.comments.size}"
    assert segments.any? { |segment| segment.include?("Published") }
  end

  test "#post_metadata_segments should include withdraw link when permitted" do
    feed = create(:feed)

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source"
    )

    segments = post_metadata_segments(post, withdraw_allowed: true)

    assert segments.any? { |segment| segment.include?("Withdraw") }
  end

  test "#format_post_content should return empty string for nil content" do
    assert_equal "", format_post_content(nil)
  end

  test "#format_post_content should return empty string for blank content" do
    assert_equal "", format_post_content("")
    assert_equal "", format_post_content("   ")
  end

  test "#format_post_content should trim leading and trailing whitespace" do
    content = "  Hello world  "
    result = format_post_content(content)
    assert_includes result, "Hello world"
    assert_not_includes result, "  Hello world  "
  end

  test "#format_post_content should convert URLs to links" do
    content = "Check out https://example.com for more info"
    result = format_post_content(content)
    assert_includes result, '<a href="https://example.com"'
    assert_includes result, 'target="_blank"'
    assert_includes result, 'rel="noopener"'
    assert_includes result, 'class="ff-link"'
  end

  test "#format_post_content should convert single line breaks to br tags" do
    content = "Line 1\nLine 2"
    result = format_post_content(content)
    assert_includes result, "Line 1<br>Line 2"
  end

  test "#format_post_content should create paragraphs from double line breaks" do
    content = "Paragraph 1\n\nParagraph 2"
    result = format_post_content(content)
    paragraphs = css_select(Nokogiri::HTML.fragment(result), "p")
    assert_equal 2, paragraphs.size
    assert_includes paragraphs[0].text, "Paragraph 1"
    assert_includes paragraphs[1].text, "Paragraph 2"
  end

  test "#format_post_content should create paragraphs from CRLF line breaks" do
    content = "Paragraph 1\r\n\r\nParagraph 2"
    result = format_post_content(content)

    # Should create 2 paragraphs, not 1 paragraph with <br><br>
    paragraphs = css_select(Nokogiri::HTML.fragment(result), "p")
    assert_equal 2, paragraphs.size
    assert_includes paragraphs[0].text, "Paragraph 1"
    assert_includes paragraphs[1].text, "Paragraph 2"

    # Should not have double <br> tags
    assert_not_includes result, "<br><br>"
  end

  test "#format_post_content should escape HTML to prevent XSS" do
    content = "<script>alert('xss')</script>"
    result = format_post_content(content)
    assert_includes result, "&lt;script&gt;"
    assert_not_includes result, "<script>"
  end

  test "#format_post_content should escape malicious URLs to prevent XSS" do
    content = 'Check out https://evil.com" onmouseover="alert(1) for details'
    result = format_post_content(content)

    # URL should be escaped in href attribute
    assert_includes result, 'href="https://evil.com&quot;'
    # Event handler should be escaped and not executable
    assert_includes result, "onmouseover=&quot;alert(1)"
    # Should not contain unescaped quotes that would break out of href
    assert_not_includes result, 'href="https://evil.com"'
  end

  test "#format_post_content should handle complex content with URLs and line breaks" do
    content = "Check this out:\nhttps://example.com\n\nThis is a second paragraph."
    result = format_post_content(content)

    # Should have 2 paragraphs
    paragraphs = css_select(Nokogiri::HTML.fragment(result), "p")
    assert_equal 2, paragraphs.size

    # First paragraph should have a br tag and a link
    assert_includes paragraphs[0].to_html, "<br>"
    assert_includes paragraphs[0].to_html, '<a href="https://example.com"'

    # Second paragraph should have the text
    assert_includes paragraphs[1].text, "This is a second paragraph."
  end
end
