require "test_helper"

class AdminPolicyTest < ActiveSupport::TestCase
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

  def policy_for_user(current_user)
    AdminPolicy.new(current_user, :admin)
  end

  test "should deny show access to regular users" do
    policy = policy_for_user(user)
    assert_not policy.show?
  end

  test "should allow show access to admin users" do
    policy = policy_for_user(admin_user)
    assert policy.show?
  end

  test "should deny show access to nil user" do
    policy = AdminPolicy.new(nil, :admin)
    assert_not policy.show?
  end

  test "should deny show access to user without admin permission" do
    user_without_permissions = create(:user)
    policy = policy_for_user(user_without_permissions)
    assert_not policy.show?
  end
end