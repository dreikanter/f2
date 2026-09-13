require "test_helper"

class PostPublicationTest < ActiveSupport::TestCase
  test ".create! should reject a second publication checkpoint for the same post" do
    post = create(:post)
    PostPublication.create!(post: post)

    assert_raises(ActiveRecord::RecordInvalid) do
      PostPublication.create!(post: post)
    end
  end

  test "#destroy! should remove the post's publication checkpoint" do
    post = create(:post)
    PostPublication.create!(post: post)

    assert_difference("PostPublication.count", -1) { post.destroy! }
  end

  test "#withdraw! should remove the publication checkpoint" do
    post = create(:post, :published)
    publication = PostPublication.create!(post: post)

    post.withdraw!

    assert_predicate post.reload, :withdrawn?
    assert_not PostPublication.exists?(publication.id)
  end
end
