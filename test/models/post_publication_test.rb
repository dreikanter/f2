require "test_helper"

class PostPublicationTest < ActiveSupport::TestCase
  test "a post has at most one publication checkpoint" do
    post = create(:post)
    PostPublication.create!(post: post)

    assert_raises(ActiveRecord::RecordInvalid) do
      PostPublication.create!(post: post)
    end
  end

  test "destroying a post removes its publication checkpoint" do
    post = create(:post)
    PostPublication.create!(post: post)

    assert_difference("PostPublication.count", -1) { post.destroy! }
  end

  test "moving a post out of active publication removes its checkpoint" do
    post = create(:post, :published)
    publication = PostPublication.create!(post: post)

    post.withdrawn!

    assert_not PostPublication.exists?(publication.id)
  end
end
