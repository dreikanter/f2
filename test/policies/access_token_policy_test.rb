require "test_helper"

class AccessTokenPolicyTest < ActiveSupport::TestCase
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

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  def other_access_token
    @other_access_token ||= create(:access_token, user: other_user)
  end

  def policy_for_user(current_user, token = access_token)
    AccessTokenPolicy.new(current_user, token)
  end

  def scope_for_user(current_user)
    AccessTokenPolicy::Scope.new(current_user, AccessToken.all)
  end

  test "should allow index access to authenticated users" do
    policy = policy_for_user(user)
    assert policy.index?
  end

  test "should deny index access to nil user" do
    policy = AccessTokenPolicy.new(nil, access_token)
    assert_not policy.index?
  end

  test "should allow show access to token owner" do
    policy = policy_for_user(user, access_token)
    assert policy.show?
  end

  test "should deny show access to other users" do
    policy = policy_for_user(user, other_access_token)
    assert_not policy.show?
  end

  test "should allow show access to admin users" do
    policy = policy_for_user(admin_user, access_token)
    assert policy.show?
  end

  test "should allow create access to authenticated users" do
    policy = policy_for_user(user)
    assert policy.create?
  end

  test "should deny create access to nil user" do
    policy = AccessTokenPolicy.new(nil, access_token)
    assert_not policy.create?
  end

  test "should allow update access to token owner" do
    policy = policy_for_user(user, access_token)
    assert policy.update?
  end

  test "should deny update access to other users" do
    policy = policy_for_user(user, other_access_token)
    assert_not policy.update?
  end

  test "should allow update access to admin users" do
    policy = policy_for_user(admin_user, access_token)
    assert policy.update?
  end

  test "should allow destroy access to token owner" do
    policy = policy_for_user(user, access_token)
    assert policy.destroy?
  end

  test "should deny destroy access to other users" do
    policy = policy_for_user(user, other_access_token)
    assert_not policy.destroy?
  end

  test "should allow destroy access to admin users" do
    policy = policy_for_user(admin_user, access_token)
    assert policy.destroy?
  end

  test "should handle nil user gracefully" do
    policy = AccessTokenPolicy.new(nil, access_token)

    assert_not policy.index?
    assert_not policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
  end

  test "scope should return only owned tokens for regular users" do
    user_token = create(:access_token, user: user)
    other_token = create(:access_token, user: other_user)

    scope = scope_for_user(user)
    result = scope.resolve

    assert_includes result, user_token
    assert_not_includes result, other_token
  end

  test "scope should return all tokens for admin users" do
    user_token = create(:access_token, user: user)
    other_token = create(:access_token, user: other_user)

    scope = scope_for_user(admin_user)
    result = scope.resolve

    assert_includes result, user_token
    assert_includes result, other_token
  end

  test "scope should return no tokens for nil user" do
    create(:access_token, user: user)

    scope = AccessTokenPolicy::Scope.new(nil, AccessToken.all)
    result = scope.resolve

    assert_equal 0, result.count
  end

  test "owner_or_admin? returns true for token owner" do
    policy = policy_for_user(user, access_token)
    assert policy.send(:owner_or_admin?)
  end

  test "owner_or_admin? returns false for other users" do
    policy = policy_for_user(user, other_access_token)
    assert_not policy.send(:owner_or_admin?)
  end

  test "owner_or_admin? returns true for admin users" do
    policy = policy_for_user(admin_user, other_access_token)
    assert policy.send(:owner_or_admin?)
  end

  test "owner_or_admin? returns false for nil user" do
    policy = AccessTokenPolicy.new(nil, access_token)
    assert_not policy.send(:owner_or_admin?)
  end
end
