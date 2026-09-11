module Admin::UsersHelper
  def admin_user_link(user)
    link_to(user.name.presence || user.email_address, admin_user_path(user), class: class_names(text_link_classes, "font-medium"))
  end

  def admin_user_actions_menu_items(user, can_suspend:)
    confirm_email = if user.email_confirmed?
      { label: "Confirm Email…", disabled: true,
        title: "This user's email is already confirmed",
        data: { key: "actions.confirm_email_disabled" } }
    else
      modal_trigger_menu_item("Confirm Email…", key: "actions.confirm_email",
                              modal_id: "confirm-email-modal-#{user.id}")
    end

    suspension = if user.suspended?
      modal_trigger_menu_item("Unsuspend user…", key: "actions.unsuspend",
                              modal_id: "unsuspend-user-modal-#{user.id}")
    elsif can_suspend
      modal_trigger_menu_item("Suspend user…", key: "actions.suspend",
                              modal_id: "suspend-user-modal-#{user.id}")
    else
      { label: "Suspend user…", disabled: true,
        title: "You can't suspend your own account",
        data: { key: "actions.suspend_self_disabled" } }
    end

    [
      confirm_email,
      { label: "Change Email", href: edit_admin_user_email_update_path(user),
        data: { key: "actions.change_email" } },
      modal_trigger_menu_item("Reset Password…", key: "actions.reset_password",
                              modal_id: "password-reset-modal-#{user.id}"),
      { separator: true },
      suspension
    ]
  end
end
