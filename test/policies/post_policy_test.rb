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

  test "#index? should allow authenticated users" do
    assert PostPolicy.new(user, Post).index?
  end

  test "#index? should deny unauthenticated users" do
    assert_not PostPolicy.new(nil, Post).index?
  end

  test "#index? should deny onboarding users" do
    onboarding_user = create(:user, :onboarding)
    assert_not PostPolicy.new(onboarding_user, Post).index?
  end

  test "#show? should allow owner" do
    assert PostPolicy.new(user, user_post).show?
  end

  test "#show? should deny non-owner" do
    assert_not PostPolicy.new(user, other_user_post).show?
  end

  test "#show? should deny unauthenticated users" do
    assert_not PostPolicy.new(nil, user_post).show?
  end

  test "Scope returns user's posts only" do
    create(:post, feed: feed)
    create(:post, feed: other_feed)

    resolved_posts = PostPolicy::Scope.new(user, Post).resolve
    assert_equal 1, resolved_posts.count
    assert_equal feed.id, resolved_posts.first.feed_id
  end

  test "#destroy? should allow owner for published post" do
    published_post = create(:post, :published, feed: feed)
    assert PostPolicy.new(user, published_post).destroy?
  end

  test "#destroy? should deny owner for non-published post" do
    draft_post = create(:post, :draft, feed: feed)
    assert_not PostPolicy.new(user, draft_post).destroy?
  end

  test "#destroy? should allow admin for published post" do
    admin_user = create(:user, :admin)
    published_post = create(:post, :published, feed: other_feed)
    assert PostPolicy.new(admin_user, published_post).destroy?
  end

  test "#destroy? should deny non-admin non-owner for published post" do
    published_post = create(:post, :published, feed: other_feed)
    assert_not PostPolicy.new(user, published_post).destroy?
  end

  test "#destroy? should deny unauthenticated users" do
    published_post = create(:post, :published, feed: feed)
    assert_not PostPolicy.new(nil, published_post).destroy?
  end

  test "Scope should return empty for unauthenticated users" do
    create(:post, feed: feed)
    resolved_posts = PostPolicy::Scope.new(nil, Post).resolve
    assert_equal 0, resolved_posts.count
  end
end
