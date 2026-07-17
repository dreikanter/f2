require "test_helper"

class PostPublicationTest < ActiveSupport::TestCase
  test "a post has at most one publication checkpoint" do
    post = create(:post)
    post.create_post_publication!

    assert_raises(ActiveRecord::RecordInvalid) do
      post.create_post_publication!
    end
  end

  test "destroying a post removes its publication checkpoint" do
    post = create(:post)
    post.create_post_publication!

    assert_difference("PostPublication.count", -1) { post.destroy! }
  end
end
