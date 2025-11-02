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
    assert_includes card.text, "UID post-123"
    assert_includes card.text, "Published about 1 hour ago"
    assert_includes card.text, "Attachments: 1"
    assert_includes card.text, "Hello world"
    assert_includes card.css("a").map(&:text), "View source"
  end

  test "handles bad published_at values without crashing" do
    post_data = { "published_at" => "not-a-date" }

    Rails.logger.stub(:warn, nil) do
      result = render_inline(PostPreviewComponent.new(post_data: post_data))
      refute_includes result.text, "Published"
    end
  end

  test "omits attachments section when not present" do
    post_data = { "content" => "Text only" }

    result = render_inline(PostPreviewComponent.new(post_data: post_data))

    refute_includes result.text, "Attachments"
    assert_includes result.text, "Text only"
  end
end
