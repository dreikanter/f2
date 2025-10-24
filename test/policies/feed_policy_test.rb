require "test_helper"

class FeedPolicyTest < ActiveSupport::TestCase
  def user
    users(:user)
  end

  def other_user
    users(:other_user)
  end

  def admin_user
    users(:admin_user)
  end

  def feed
    feeds(:feed)
  end

  def other_feed
    feeds(:other_feed)
  end

  def policy_for_user(current_user, target_feed = feed)
    FeedPolicy.new(current_user, target_feed)
  end

  def scope_for_user(current_user)
    FeedPolicy::Scope.new(current_user, Feed.all)
  end

  test "should allow index access to authenticated users" do
    policy = policy_for_user(user)
    assert policy.index?
  end

  test "should deny index access to nil user" do
    policy = FeedPolicy.new(nil, feed)
    assert_not policy.index?
  end

  test "should deny index access to onboarding users" do
    onboarding_user = create(:user, :onboarding)
    policy = FeedPolicy.new(onboarding_user, feed)
    assert_not policy.index?
  end

  test "should allow show access to feed owner" do
    policy = policy_for_user(user, feed)
    assert policy.show?
  end

  test "should deny show access to other users" do
    policy = policy_for_user(user, other_feed)
    assert_not policy.show?
  end

  test "should allow create access to authenticated users" do
    policy = policy_for_user(user)
    assert policy.create?
  end

  test "should deny create access to nil user" do
    policy = FeedPolicy.new(nil, feed)
    assert_not policy.create?
  end

  test "should allow update access to feed owner" do
    policy = policy_for_user(user, feed)
    assert policy.update?
  end

  test "should deny update access to other users" do
    policy = policy_for_user(user, other_feed)
    assert_not policy.update?
  end

  test "should allow destroy access to feed owner" do
    policy = policy_for_user(user, feed)
    assert policy.destroy?
  end

  test "should deny destroy access to other users" do
    policy = policy_for_user(user, other_feed)
    assert_not policy.destroy?
  end

  test "should allow purge access to feed owner" do
    policy = policy_for_user(user, feed)
    assert policy.purge?
  end

  test "should deny purge access to other users" do
    policy = policy_for_user(user, other_feed)
    assert_not policy.purge?
  end

  test "should handle nil user gracefully" do
    policy = FeedPolicy.new(nil, feed)

    assert_not policy.index?
    assert_not policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
    assert_not policy.purge?
  end

  test "scope should return only owned feeds for regular users" do
    scope = scope_for_user(user)
    result = scope.resolve

    assert_includes result, feed
    assert_not_includes result, other_feed
  end

  test "scope should return no feeds for nil user" do
    scope = FeedPolicy::Scope.new(nil, Feed.all)
    result = scope.resolve

    assert_equal 0, result.count
  end

  test "owner? returns true for feed owner" do
    policy = policy_for_user(user, feed)
    assert policy.send(:owner?)
  end

  test "owner? returns false for other users" do
    policy = policy_for_user(user, other_feed)
    assert_not policy.send(:owner?)
  end

  test "owner? returns false for nil user" do
    policy = FeedPolicy.new(nil, feed)
    assert_not policy.send(:owner?)
  end
end
