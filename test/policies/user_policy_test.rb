require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def admin_user
    @admin_user ||= begin
      admin = create(:user)
      create(:permission, user: admin, name: "admin")
      admin
    end
  end

  def policy_for_user(current_user, target_user)
    UserPolicy.new(current_user, target_user)
  end

  def scope_for_user(current_user)
    UserPolicy::Scope.new(current_user, User.all)
  end

  test "should allow show access to self" do
    policy = policy_for_user(user, user)
    assert policy.show?
  end

  test "should deny show access to other users" do
    policy = policy_for_user(user, other_user)
    assert_not policy.show?
  end

  test "should allow show access to admin users" do
    policy = policy_for_user(admin_user, user)
    assert policy.show?
  end

  test "should allow update access to self" do
    policy = policy_for_user(user, user)
    assert policy.update?
  end

  test "should deny update access to other users" do
    policy = policy_for_user(user, other_user)
    assert_not policy.update?
  end

  test "should allow update access to admin users" do
    policy = policy_for_user(admin_user, user)
    assert policy.update?
  end

  test "should deny destroy access to regular users" do
    policy = policy_for_user(user, user)
    assert_not policy.destroy?
  end

  test "should deny destroy access to other users" do
    policy = policy_for_user(user, other_user)
    assert_not policy.destroy?
  end

  test "should allow destroy access to admin users" do
    policy = policy_for_user(admin_user, user)
    assert policy.destroy?
  end

  test "should handle nil user gracefully" do
    policy = UserPolicy.new(nil, user)

    assert_not policy.show?
    assert_not policy.update?
    assert_not policy.destroy?
  end

  test "scope should return only self for regular users" do
    scope = scope_for_user(user)
    result = scope.resolve

    assert_equal 1, result.count
    assert_includes result, user
    assert_not_includes result, other_user
  end

  test "scope should return all users for admin users" do
    scope = scope_for_user(admin_user)
    result = scope.resolve

    assert_includes result, user
    assert_includes result, other_user
    assert_includes result, admin_user
  end

  test "scope should return no users for nil user" do
    scope = UserPolicy::Scope.new(nil, User.all)
    result = scope.resolve

    assert_equal 0, result.count
  end

  test "self_or_admin? returns true for self" do
    policy = policy_for_user(user, user)
    assert policy.send(:self_or_admin?)
  end

  test "self_or_admin? returns false for other users" do
    policy = policy_for_user(user, other_user)
    assert_not policy.send(:self_or_admin?)
  end

  test "self_or_admin? returns true for admin users" do
    policy = policy_for_user(admin_user, other_user)
    assert policy.send(:self_or_admin?)
  end
end