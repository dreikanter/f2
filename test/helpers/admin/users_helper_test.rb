require "test_helper"

class Admin::UsersHelperTest < ActionView::TestCase
  test "#admin_user_actions_menu_items should list account actions before suspension" do
    user = create(:user, :inactive)

    items = admin_user_actions_menu_items(user, can_suspend: true)

    assert_equal ["Confirm Email…", "Change Email", "Reset Password…", nil, "Suspend user…"],
                 items.map { _1[:label] }
    assert items[-2][:separator]
  end

  test "#admin_user_actions_menu_items should wire routes and confirmation dialogs" do
    user = create(:user, :inactive)
    items = admin_user_actions_menu_items(user, can_suspend: true)
              .reject { _1[:separator] }.index_by { _1[:label] }

    assert_equal "confirm-email-modal-#{user.id}",
                 items["Confirm Email…"].dig(:data, :modal_trigger_modal_id_value)
    assert_equal edit_admin_user_email_update_path(user), items["Change Email"][:href]
    assert_equal "password-reset-modal-#{user.id}",
                 items["Reset Password…"].dig(:data, :modal_trigger_modal_id_value)
    assert_equal "suspend-user-modal-#{user.id}",
                 items["Suspend user…"].dig(:data, :modal_trigger_modal_id_value)
  end

  test "#admin_user_actions_menu_items should disable actions that do not apply" do
    user = create(:user, state: :active)
    items = admin_user_actions_menu_items(user, can_suspend: false)
              .reject { _1[:separator] }.index_by { _1[:label] }

    assert items["Confirm Email…"][:disabled]
    assert items["Suspend user…"][:disabled]
  end

  test "#admin_user_actions_menu_items should offer unsuspension for a suspended user" do
    user = create(:user, :suspended)

    items = admin_user_actions_menu_items(user, can_suspend: true)

    assert_equal "Unsuspend user…", items.last[:label]
    assert_equal "unsuspend-user-modal-#{user.id}",
                 items.last.dig(:data, :modal_trigger_modal_id_value)
  end
end
