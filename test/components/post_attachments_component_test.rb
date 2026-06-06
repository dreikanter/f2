require "test_helper"
require "view_component/test_case"

class PostAttachmentsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should show attachments with accessible filenames" do
    post = create(:post, :with_attachments, feed: feed)

    result = render_inline(PostAttachmentsComponent.new(post: post))

    assert_not_nil result.css('[data-key="post.attachments"]').first
    assert_equal "image1.jpg", result.css('a[href*="image1.jpg"] span.sr-only').first.text
    assert_equal "image2.png", result.css('a[href*="image2.png"] span.sr-only').first.text
  end

  test "#render should not render when there are no attachments" do
    post = create(:post, feed: feed)

    result = render_inline(PostAttachmentsComponent.new(post: post))

    assert_empty result.css('[data-key="post.attachments"]')
  end
end
