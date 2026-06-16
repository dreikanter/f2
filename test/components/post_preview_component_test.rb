require "test_helper"
require "view_component/test_case"

class PostPreviewComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) }
  teardown { travel_back }

  test "renders preview card with metadata and content" do
    post_data = {
      "uid" => "post-123",
      "content" => "<p>Hello world</p>",
      "published_at" => 1.hour.ago.iso8601,
      "source_url" => "https://example.com/post/123",
      "attachments" => [
        { "url" => "https://example.com/attachment.png", "type" => "image" }
      ]
    }

    result = render_inline(PostPreviewComponent.new(post_data: post_data, index: 0))

    card = result.at_css("#feed-preview-post-1")
    assert_not_nil card
    assert_includes card.text, "UID:"
    assert_includes card.text, "post-123"
    assert_includes card.text, "Published:"
    assert_includes card.text, "1h"
    assert_includes card.text, "URL:"
    assert_includes card.text, "Hello world"

    source_link = card.css("a").find { |link| link["href"] == "https://example.com/post/123" }
    assert_not_nil source_link
  end

  test "omits metadata rows when fields are absent" do
    post_data = { "content" => "Body" }

    result = render_inline(PostPreviewComponent.new(post_data: post_data))

    refute_includes result.text, "UID:"
    refute_includes result.text, "Published:"
    refute_includes result.text, "URL:"
  end

  test "omits attachments section when not present" do
    post_data = { "content" => "Body", "uid" => "post-1" }

    result = render_inline(PostPreviewComponent.new(post_data: post_data))

    refute_includes result.text, "Attachments"
    assert_includes result.text, "Body"
  end

  test "renders image attachments as thumbnails linking to the originals" do
    post_data = {
      "content" => "Body",
      "attachments" => [
        { "url" => "https://example.com/photo.png", "type" => "image" },
        "https://example.com/plain.jpg"
      ]
    }

    result = render_inline(PostPreviewComponent.new(post_data: post_data))

    section = result.at_css('[data-key="preview.attachments"]')
    assert_not_nil section
    assert_not_nil section.at_css('a[href="https://example.com/photo.png"] img')
    assert_not_nil section.at_css('a[href="https://example.com/plain.jpg"] img')
  end

  test "keeps non-image attachments as links" do
    post_data = {
      "content" => "Body",
      "attachments" => [
        { "url" => "https://example.com/clip.mp4", "type" => "video" }
      ]
    }

    result = render_inline(PostPreviewComponent.new(post_data: post_data))

    section = result.at_css('[data-key="preview.attachments"]')
    assert_not_nil section
    assert_empty section.css("img")
    assert_not_nil section.at_css('a[href="https://example.com/clip.mp4"]')
  end

  test "renders content without a synthesized title heading" do
    post_data = { "content" => "Lorem ipsum dolor sit amet, the opening line of the post body" }

    result = render_inline(PostPreviewComponent.new(post_data: post_data, index: 0))

    assert_empty result.css("h1, h2, h3")
    assert_equal 1, result.text.scan("Lorem ipsum").size
  end

  test "handles bad published_at values without crashing" do
    post_data = { "published_at" => "not-a-date" }

    Rails.logger.stub(:warn, nil) do
      result = render_inline(PostPreviewComponent.new(post_data: post_data))
      refute_includes result.text, "Published:"
    end
  end

  test "#published_compact should return compact duration for recent times" do
    component = PostPreviewComponent.new(post_data: { "published_at" => 7.hours.ago.iso8601 })
    assert_equal "7h", component.published_compact

    component = PostPreviewComponent.new(post_data: { "published_at" => 45.minutes.ago.iso8601 })
    assert_equal "45m", component.published_compact

    component = PostPreviewComponent.new(post_data: { "published_at" => 3.days.ago.iso8601 })
    assert_equal "3d", component.published_compact
  end

  test "#published_compact should return nil when published_at is absent" do
    component = PostPreviewComponent.new(post_data: {})
    assert_nil component.published_compact
  end
end
