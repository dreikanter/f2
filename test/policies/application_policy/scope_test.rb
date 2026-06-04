require "test_helper"

class ApplicationPolicy::ScopeTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def scope_for(current_user)
    ApplicationPolicy::Scope.new(current_user, User)
  end

  test "Scope initializes with user and scope" do
    scope = scope_for(admin_user)

    assert_equal admin_user, scope.send(:user)
    assert_equal User, scope.send(:scope)
  end

  test "Scope resolve raises NotImplementedError by default" do
    error = assert_raises NotImplementedError do
      scope_for(admin_user).resolve
    end

    assert_includes error.message, "You must define #resolve in ApplicationPolicy::Scope"
  end

  test "#admin? should return true for admin users" do
    assert scope_for(admin_user).send(:admin?)
  end

  test "#admin? should return false for regular users" do
    assert_not scope_for(regular_user).send(:admin?)
  end

  test "#admin? should return false for nil user" do
    assert_not scope_for(nil).send(:admin?)
  end

  test "#dev? should return true for dev users" do
    assert scope_for(dev_user).send(:dev?)
  end

  test "#dev? should return false for regular users" do
    assert_not scope_for(regular_user).send(:dev?)
  end

  test "#dev? should return false for nil user" do
    assert_not scope_for(nil).send(:dev?)
  end
end
