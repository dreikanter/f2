require "test_helper"

class FeedProfilePolicyTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def admin_user
    @admin_user ||= begin
      admin = create(:user)
      create(:permission, user: admin, name: "admin")
      admin
    end
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile)
  end

  def policy_for_user(user)
    FeedProfilePolicy.new(user, feed_profile)
  end

  def scope_for_user(user)
    FeedProfilePolicy::Scope.new(user, FeedProfile.all)
  end

  test "should deny index access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.index?
  end

  test "should allow index access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.index?
  end

  test "should deny show access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.show?
  end

  test "should allow show access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.show?
  end

  test "should deny create access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.create?
  end

  test "should allow create access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.create?
  end

  test "should deny update access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.update?
  end

  test "should allow update access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.update?
  end

  test "should deny destroy access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.destroy?
  end

  test "should allow destroy access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.destroy?
  end

  test "should deny edit access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.edit?
  end

  test "should allow edit access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.edit?
  end

  test "should deny new access to non-admin users" do
    policy = policy_for_user(user)
    assert_not policy.new?
  end

  test "should allow new access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.new?
  end

  test "scope should return no records for non-admin users" do
    create(:feed_profile, name: "test-profile-1")
    create(:feed_profile, name: "test-profile-2")

    scope = scope_for_user(user)
    result = scope.resolve

    assert_equal 0, result.count
  end

  test "scope should return all records for admin users" do
    profile1 = create(:feed_profile, name: "test-profile-1")
    profile2 = create(:feed_profile, name: "test-profile-2")

    scope = scope_for_user(admin_user)
    result = scope.resolve

    assert_includes result, profile1
    assert_includes result, profile2
  end

  test "should handle nil user gracefully" do
    policy = FeedProfilePolicy.new(nil, feed_profile)

    assert_not policy.index?
    assert_not policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
  end

  test "scope should handle nil user gracefully" do
    create(:feed_profile, name: "test-profile")

    scope = FeedProfilePolicy::Scope.new(nil, FeedProfile.all)
    result = scope.resolve

    assert_equal 0, result.count
  end
end
