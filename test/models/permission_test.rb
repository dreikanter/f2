require "test_helper"

class PermissionTest < ActiveSupport::TestCase
  test "should be valid with user and valid name" do
    permission = build(:permission)
    assert permission.valid?
  end

  test "should belong to user" do
    user = create(:user)
    permission = create(:permission, user: user)
    assert_equal user, permission.user
  end

  test "should require name" do
    permission = build(:permission, name: nil)
    assert_not permission.valid?
    assert permission.errors.of_kind?(:name, :blank)
  end

  test "should require user" do
    permission = build(:permission, user: nil)
    assert_not permission.valid?
    assert permission.errors.of_kind?(:user, :blank)
  end

  test "should validate name is in available permissions" do
    permission = build(:permission, name: "invalid_permission")
    assert_not permission.valid?
    assert permission.errors.of_kind?(:name, :inclusion)
  end

  test "should not allow duplicate permission for same user" do
    user = create(:user)
    create(:permission, user: user, name: "admin")
    duplicate_permission = build(:permission, user: user, name: "admin")

    assert_not duplicate_permission.valid?
    assert duplicate_permission.errors.of_kind?(:user_id, :taken)
  end

  test "should allow same permission for different users" do
    user1 = create(:user)
    user2 = create(:user)

    create(:permission, user: user1, name: "admin")
    permission = build(:permission, user: user2, name: "admin")

    assert permission.valid?
  end
end
