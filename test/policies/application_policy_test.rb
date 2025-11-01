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

  def sample_record
    @sample_record ||= create(:user)
  end

  test "#initialize should set user and record" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_equal admin_user, policy.user
    assert_equal sample_record, policy.record
  end

  test "#initialize should allow nil user" do
    policy = ApplicationPolicy.new(nil, sample_record)

    assert_nil policy.user
    assert_equal sample_record, policy.record
  end

  test "#index? should return false by default" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_not policy.index?
  end

  test "#show? should return false by default" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_not policy.show?
  end

  test "#create? should return false by default" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_not policy.create?
  end

  test "#new? should delegate to #create?" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    # Mock create? to return true
    policy.define_singleton_method(:create?) { true }
    assert policy.new?

    # Mock create? to return false
    policy.define_singleton_method(:create?) { false }
    assert_not policy.new?
  end

  test "#update? should return false by default" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_not policy.update?
  end

  test "#edit? should delegate to #update?" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    # Mock update? to return true
    policy.define_singleton_method(:update?) { true }
    assert policy.edit?

    # Mock update? to return false
    policy.define_singleton_method(:update?) { false }
    assert_not policy.edit?
  end

  test "#destroy? should return false by default" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert_not policy.destroy?
  end

  test "#admin? should return true for admin users" do
    policy = ApplicationPolicy.new(admin_user, sample_record)

    assert policy.send(:admin?)
  end

  test "#admin? should return false for regular users" do
    policy = ApplicationPolicy.new(regular_user, sample_record)

    assert_not policy.send(:admin?)
  end

  test "#admin? should return false for nil user" do
    policy = ApplicationPolicy.new(nil, sample_record)

    assert_not policy.send(:admin?)
  end

  test "#admin? should return false when user lacks permissions" do
    user_without_permissions = create(:user)
    policy = ApplicationPolicy.new(user_without_permissions, sample_record)

    assert_not policy.send(:admin?)
  end
end
