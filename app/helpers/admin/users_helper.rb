module Admin::UsersHelper
  USER_LINK_CLASSES = "font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover".freeze

  def admin_user_link(user)
    link_to(user.name.presence || user.email_address, admin_user_path(user), class: USER_LINK_CLASSES)
  end
end
