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
    doc = Nokogiri::HTML.fragment(result)
    assert_includes doc.text, "Hello world"
    assert_not_includes doc.text, "  Hello world  "
  end

  test "#format_post_content should convert URLs to links" do
    content = "Check out https://example.com for more info"
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)
    link = css_select(doc, "a").first

    assert_not_nil link
    assert_equal "https://example.com", link["href"]
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
    assert_equal "ff-link", link["class"]
    assert_equal "https://example.com", link.text
  end

  test "#format_post_content should convert single line breaks to br tags" do
    content = "Line 1\nLine 2"
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)
    br_tags = css_select(doc, "br")

    assert_equal 1, br_tags.size
    assert_includes doc.text, "Line 1"
    assert_includes doc.text, "Line 2"
  end

  test "#format_post_content should create paragraphs from double line breaks" do
    content = "Paragraph 1\n\nParagraph 2"
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)
    paragraphs = css_select(doc, "p")

    assert_equal 2, paragraphs.size
    assert_includes paragraphs[0].text, "Paragraph 1"
    assert_includes paragraphs[1].text, "Paragraph 2"
  end

  test "#format_post_content should create paragraphs from CRLF line breaks" do
    content = "Paragraph 1\r\n\r\nParagraph 2"
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)

    # Should create 2 paragraphs, not 1 paragraph with <br><br>
    paragraphs = css_select(doc, "p")
    assert_equal 2, paragraphs.size
    assert_includes paragraphs[0].text, "Paragraph 1"
    assert_includes paragraphs[1].text, "Paragraph 2"

    # Should not have consecutive <br> tags in any paragraph
    paragraphs.each do |para|
      assert_not_includes para.inner_html, "<br><br>"
    end
  end

  test "#format_post_content should escape HTML to prevent XSS" do
    content = "<script>alert('xss')</script>"
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)

    # Should not contain executable script tags
    assert_equal 0, css_select(doc, "script").size
    # Script content should be escaped and appear as text
    assert_includes doc.text, "<script>alert('xss')</script>"
  end

  test "#format_post_content should escape malicious URLs to prevent XSS" do
    content = 'Check out https://evil.com" onmouseover="alert(1) for details'
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)
    link = css_select(doc, "a").first

    # URL should be properly escaped in href attribute
    assert_not_nil link
    assert_equal 'https://evil.com" onmouseover="alert(1)', link["href"]
    # Link should not have an onmouseover attribute
    assert_nil link["onmouseover"]
    # The malicious part should appear as text content after the link
    assert_includes doc.text, "for details"
  end

  test "#format_post_content should handle complex content with URLs and line breaks" do
    content = "Check this out:\nhttps://example.com\n\nThis is a second paragraph."
    result = format_post_content(content)
    doc = Nokogiri::HTML.fragment(result)

    # Should have 2 paragraphs
    paragraphs = css_select(doc, "p")
    assert_equal 2, paragraphs.size

    # First paragraph should have a br tag and a link
    first_para_br = css_select(paragraphs[0], "br")
    first_para_link = css_select(paragraphs[0], "a").first
    assert_equal 1, first_para_br.size
    assert_not_nil first_para_link
    assert_equal "https://example.com", first_para_link["href"]

    # Second paragraph should have the text
    assert_includes paragraphs[1].text, "This is a second paragraph."
  end
end
