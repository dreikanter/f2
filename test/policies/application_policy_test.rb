require "test_helper"

class ApplicationPolicyTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  def test_record
    @test_record ||= create(:event)
  end

  test "initializes with user and record" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_equal admin_user, policy.user
    assert_equal test_record, policy.record
  end

  test "initializes with nil user" do
    policy = ApplicationPolicy.new(nil, test_record)

    assert_nil policy.user
    assert_equal test_record, policy.record
  end

  test "index? returns false by default" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_not policy.index?
  end

  test "show? returns false by default" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_not policy.show?
  end

  test "create? returns false by default" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_not policy.create?
  end

  test "new? delegates to create?" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    # Mock create? to return true
    policy.define_singleton_method(:create?) { true }
    assert policy.new?

    # Mock create? to return false
    policy.define_singleton_method(:create?) { false }
    assert_not policy.new?
  end

  test "update? returns false by default" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_not policy.update?
  end

  test "edit? delegates to update?" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    # Mock update? to return true
    policy.define_singleton_method(:update?) { true }
    assert policy.edit?

    # Mock update? to return false
    policy.define_singleton_method(:update?) { false }
    assert_not policy.edit?
  end

  test "destroy? returns false by default" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert_not policy.destroy?
  end

  test "admin? returns true for admin users" do
    policy = ApplicationPolicy.new(admin_user, test_record)

    assert policy.send(:admin?)
  end

  test "admin? returns false for regular users" do
    policy = ApplicationPolicy.new(regular_user, test_record)

    assert_not policy.send(:admin?)
  end

  test "admin? returns false for nil user" do
    policy = ApplicationPolicy.new(nil, test_record)

    assert_not policy.send(:admin?)
  end

  test "admin? returns false when user has no permissions" do
    user_without_permissions = create(:user)
    policy = ApplicationPolicy.new(user_without_permissions, test_record)

    assert_not policy.send(:admin?)
  end

  test "Scope initializes with user and scope" do
    scope = ApplicationPolicy::Scope.new(admin_user, Event)

    assert_equal admin_user, scope.send(:user)
    assert_equal Event, scope.send(:scope)
  end

  test "Scope resolve raises NotImplementedError by default" do
    scope = ApplicationPolicy::Scope.new(admin_user, Event)

    error = assert_raises NotImplementedError do
      scope.resolve
    end
    
    assert_includes error.message, "You must define #resolve in ApplicationPolicy::Scope"
  end
end