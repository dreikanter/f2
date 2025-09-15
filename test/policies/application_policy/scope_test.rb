require "test_helper"

class ApplicationPolicy::ScopeTest < ActiveSupport::TestCase
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def arbitrary_model_class
    User
  end

  test "Scope initializes with user and scope" do
    scope = ApplicationPolicy::Scope.new(admin_user, arbitrary_model_class)

    assert_equal admin_user, scope.send(:user)
    assert_equal arbitrary_model_class, scope.send(:scope)
  end

  test "Scope resolve raises NotImplementedError by default" do
    scope = ApplicationPolicy::Scope.new(admin_user, arbitrary_model_class)

    error = assert_raises NotImplementedError do
      scope.resolve
    end

    assert_includes error.message, "You must define #resolve in ApplicationPolicy::Scope"
  end
end
