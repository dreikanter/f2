require "test_helper"

class DevPolicyTest < ActiveSupport::TestCase
  def policy_for(current_user)
    DevPolicy.new(current_user, :dev)
  end

  test "#show? should deny access to regular users" do
    policy = policy_for(users(:user))
    assert_not policy.show?
  end

  test "#show? should deny access to nil user" do
    policy = DevPolicy.new(nil, :dev)
    assert_not policy.show?
  end

  test "#show? should allow access to dev users" do
    dev_user = create(:user)
    dev_user.permissions.create!(name: "dev")
    policy = policy_for(dev_user)
    assert policy.show?
  end
end
