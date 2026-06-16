require "test_helper"
require "view_component/test_case"

class PostAttachmentsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should show attachment thumbnails linking to the originals" do
    post = create(:post, :with_attachments, feed: feed)

    result = render_inline(PostAttachmentsComponent.new(post: post))

    assert_not_nil result.css('[data-key="post.attachments"]').first
    assert_not_nil result.css('a[href="https://example.com/image1.jpg"] img').first
    assert_equal "image1.jpg", result.css('img[alt="image1.jpg"]').first["alt"]
    assert_equal "image2.png", result.css('img[alt="image2.png"]').first["alt"]
  end

  test "#render should fall back to the source url when imgproxy is unconfigured" do
    post = create(:post, :with_attachments, feed: feed)

    Rails.application.credentials.stub(:imgproxy, nil) do
      result = render_inline(PostAttachmentsComponent.new(post: post))

      assert_equal "https://example.com/image1.jpg", result.css('img[alt="image1.jpg"]').first["src"]
    end
  end

  test "#render should not render when there are no attachments" do
    post = create(:post, feed: feed)

    result = render_inline(PostAttachmentsComponent.new(post: post))

    assert_empty result.css('[data-key="post.attachments"]')
  end
end
