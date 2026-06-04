require "test_helper"

class AccessPolicyTest < ActiveSupport::TestCase
  def policy_for(current_user)
    AccessPolicy.new(current_user, :access)
  end

  test "#admin? should allow admin users" do
    assert policy_for(users(:admin_user)).admin?
  end

  test "#admin? should deny regular users" do
    assert_not policy_for(users(:user)).admin?
  end

  test "#admin? should deny nil user" do
    assert_not AccessPolicy.new(nil, :access).admin?
  end

  test "#dev? should allow dev users" do
    assert policy_for(create(:user, :dev)).dev?
  end

  test "#dev? should deny regular users" do
    assert_not policy_for(users(:user)).dev?
  end

  test "#dev? should deny nil user" do
    assert_not AccessPolicy.new(nil, :access).dev?
  end
end
