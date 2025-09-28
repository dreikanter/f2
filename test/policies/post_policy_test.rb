require "test_helper"

class PostPolicyTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def other_feed
    @other_feed ||= create(:feed, user: other_user)
  end

  def user_post
    @user_post ||= create(:post, feed: feed)
  end

  def other_user_post
    @other_user_post ||= create(:post, feed: other_feed)
  end

  test "index? allows authenticated users" do
    assert PostPolicy.new(user, Post).index?
  end

  test "index? denies unauthenticated users" do
    refute PostPolicy.new(nil, Post).index?
  end

  test "show? allows owner" do
    assert PostPolicy.new(user, user_post).show?
  end

  test "show? denies non-owner" do
    refute PostPolicy.new(user, other_user_post).show?
  end

  test "show? denies unauthenticated users" do
    refute PostPolicy.new(nil, user_post).show?
  end

  test "Scope returns user's posts only" do
    create(:post, feed: feed)
    create(:post, feed: other_feed)

    resolved_posts = PostPolicy::Scope.new(user, Post).resolve
    assert_equal 1, resolved_posts.count
    assert_equal feed.id, resolved_posts.first.feed_id
  end

  test "Scope returns empty for unauthenticated users" do
    create(:post, feed: feed)

    resolved_posts = PostPolicy::Scope.new(nil, Post).resolve
    assert_equal 0, resolved_posts.count
  end
end