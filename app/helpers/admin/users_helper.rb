module Admin::UsersHelper
  USER_LINK_CLASSES = "font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover".freeze

  def admin_user_link(user)
    link_to(user.name.presence || user.email_address, admin_user_path(user), class: USER_LINK_CLASSES)
  end

  def admin_user_actions_menu_items(user, can_suspend:)
    confirm_email = if user.email_confirmed?
      { label: "Confirm Email…", disabled: true,
        title: "This user's email is already confirmed",
        data: { key: "actions.confirm_email_disabled" } }
    else
      { label: "Confirm Email…", href: "#",
        data: { key: "actions.confirm_email", controller: "modal-trigger",
                modal_trigger_modal_id_value: "confirm-email-modal-#{user.id}",
                action: "click->modal-trigger#open" } }
    end

    suspension = if user.suspended?
      { label: "Unsuspend user…", href: "#",
        data: { key: "actions.unsuspend", controller: "modal-trigger",
                modal_trigger_modal_id_value: "unsuspend-user-modal-#{user.id}",
                action: "click->modal-trigger#open" } }
    elsif can_suspend
      { label: "Suspend user…", href: "#",
        data: { key: "actions.suspend", controller: "modal-trigger",
                modal_trigger_modal_id_value: "suspend-user-modal-#{user.id}",
                action: "click->modal-trigger#open" } }
    else
      { label: "Suspend user…", disabled: true,
        title: "You can't suspend your own account",
        data: { key: "actions.suspend_self_disabled" } }
    end

    [
      confirm_email,
      { label: "Change Email", href: edit_admin_user_email_update_path(user),
        data: { key: "actions.change_email" } },
      { label: "Reset Password…", href: "#",
        data: { key: "actions.reset_password", controller: "modal-trigger",
                modal_trigger_modal_id_value: "password-reset-modal-#{user.id}",
                action: "click->modal-trigger#open" } },
      { separator: true },
      suspension
    ]
  end
end
