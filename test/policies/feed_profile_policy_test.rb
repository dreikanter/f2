require "test_helper"

class FeedProfilePolicyTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def policy_for(current_user)
    FeedProfilePolicy.new(current_user, :feed_profile)
  end

  test "#index? should allow admin users" do
    assert policy_for(admin_user).index?
  end

  test "#index? should deny regular users" do
    assert_not policy_for(regular_user).index?
  end

  test "#show? should allow admin users" do
    assert policy_for(admin_user).show?
  end

  test "#show? should deny regular users" do
    assert_not policy_for(regular_user).show?
  end

  test "#create? should allow admin users" do
    assert policy_for(admin_user).create?
  end

  test "#create? should deny regular users" do
    assert_not policy_for(regular_user).create?
  end

  test "#update? should allow admin users" do
    assert policy_for(admin_user).update?
  end

  test "#update? should deny regular users" do
    assert_not policy_for(regular_user).update?
  end

  test "#destroy? should allow admin users" do
    assert policy_for(admin_user).destroy?
  end

  test "#destroy? should deny regular users" do
    assert_not policy_for(regular_user).destroy?
  end
end
