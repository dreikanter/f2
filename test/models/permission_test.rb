require "test_helper"

class PermissionTest < ActiveSupport::TestCase
  test "#valid? should return true with user and valid name" do
    permission = build(:permission)
    assert permission.valid?
  end

  test "#user should return the associated user" do
    user = create(:user)
    permission = create(:permission, user: user)
    assert_equal user, permission.user
  end

  test "#valid? should require name" do
    permission = build(:permission, name: nil)
    assert_not permission.valid?
    assert permission.errors.of_kind?(:name, :blank)
  end

  test "#valid? should require user" do
    permission = build(:permission, user: nil)
    assert_not permission.valid?
    assert permission.errors.of_kind?(:user, :blank)
  end

  test "#valid? should validate name is in available permissions" do
    permission = build(:permission, name: "invalid_permission")
    assert_not permission.valid?
    assert permission.errors.of_kind?(:name, :inclusion)
  end

  test "#valid? should not allow duplicate permission for same user" do
    user = create(:user)
    create(:permission, user: user, name: "admin")
    duplicate_permission = build(:permission, user: user, name: "admin")

    assert_not duplicate_permission.valid?
    assert duplicate_permission.errors.of_kind?(:user_id, :taken)
  end

  test "#valid? should allow same permission for different users" do
    user1 = create(:user)
    user2 = create(:user)

    create(:permission, user: user1, name: "admin")
    permission = build(:permission, user: user2, name: "admin")

    assert permission.valid?
  end

  test ".display_name should return capitalized display name for a permission" do
    assert_equal "Admin", Permission.display_name(Permission::ADMIN)
    assert_equal "Developer Tools", Permission.display_name(Permission::DEV)
  end

  test "#display_name should return the display name for the record's permission" do
    permission = build(:permission, name: Permission::DEV)
    assert_equal "Developer Tools", permission.display_name
  end
end
