require "test_helper"

class Admin::PermissionsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def target_user
    @target_user ||= create(:user)
  end

  test "#update should require authentication" do
    patch admin_user_permissions_path(target_user), params: { permissions: [] }

    assert_redirected_to new_session_path
  end

  test "#update should require admin permission" do
    sign_in_as create(:user)

    patch admin_user_permissions_path(target_user), params: { permissions: [] }

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#update should add a permission" do
    sign_in_as admin_user
    assert_not target_user.permission?(Permission::DEV)

    patch admin_user_permissions_path(target_user), params: { permissions: [Permission::DEV] }

    assert_redirected_to admin_user_path(target_user)
    assert_equal "Permissions updated.", flash[:success]
    assert target_user.reload.permission?(Permission::DEV)
  end

  test "#update should remove a permission" do
    sign_in_as admin_user
    create(:permission, user: target_user, name: Permission::DEV)

    patch admin_user_permissions_path(target_user), params: { permissions: [] }

    assert_redirected_to admin_user_path(target_user)
    assert_not target_user.reload.permission?(Permission::DEV)
  end

  test "#update should add multiple permissions at once" do
    sign_in_as admin_user

    patch admin_user_permissions_path(target_user), params: { permissions: [Permission::ADMIN, Permission::DEV] }

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert target_user.permission?(Permission::ADMIN)
    assert target_user.permission?(Permission::DEV)
  end

  test "#update should ignore unknown permission names" do
    sign_in_as admin_user

    patch admin_user_permissions_path(target_user), params: { permissions: ["superuser", Permission::DEV] }

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert target_user.permission?(Permission::DEV)
    assert_not target_user.permission?("superuser")
  end

  test "#update should prevent removing admin from the only admin user" do
    # Remove the fixture admin permission so admin_user is the sole admin
    permissions(:admin_permission).destroy
    sign_in_as admin_user

    patch admin_user_permissions_path(admin_user), params: { permissions: [] }

    assert_redirected_to admin_user_path(admin_user)
    assert_equal "Cannot remove the admin permission from the only admin user.", flash[:alert]
    assert admin_user.reload.permission?(Permission::ADMIN)
  end

  test "#update should succeed when only admin submits form with admin permission included" do
    permissions(:admin_permission).destroy
    sign_in_as admin_user

    patch admin_user_permissions_path(admin_user), params: { permissions: [Permission::ADMIN] }

    assert_redirected_to admin_user_path(admin_user)
    assert_equal "Permissions updated.", flash[:success]
    assert admin_user.reload.permission?(Permission::ADMIN)
  end

  test "#update should allow removing admin when multiple admins exist" do
    sign_in_as admin_user
    second_admin = create(:user, :admin)

    patch admin_user_permissions_path(second_admin), params: { permissions: [] }

    assert_redirected_to admin_user_path(second_admin)
    assert_equal "Permissions updated.", flash[:success]
    assert_not second_admin.reload.permission?(Permission::ADMIN)
  end

  test "show page should display disabled admin checkbox for the only admin" do
    permissions(:admin_permission).destroy
    sign_in_as admin_user

    get admin_user_path(admin_user)

    assert_response :success
    assert_select "input[data-key='permissions.admin'][disabled]"
  end

  test "show page should display enabled admin checkbox when multiple admins exist" do
    second_admin = create(:user, :admin)
    sign_in_as admin_user

    get admin_user_path(second_admin)

    assert_response :success
    assert_select "input[data-key='permissions.admin']:not([disabled])"
  end

  test "show page should display enabled admin checkbox for non-admin user" do
    sign_in_as admin_user

    get admin_user_path(target_user)

    assert_response :success
    assert_select "input[data-key='permissions.admin']:not([disabled])"
  end
end
