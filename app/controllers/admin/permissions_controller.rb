class Admin::PermissionsController < ApplicationController
  def update
    authorize User, :manage_permissions?
    user = User.find(params[:user_id])

    error = nil
    User.transaction do
      if removing_admin?(user) && only_admin?
        error = "Cannot remove the admin permission from the only admin user."
        raise ActiveRecord::Rollback
      end
      sync_permissions(user)
    end

    if error
      redirect_to admin_user_path(user), alert: error
    else
      redirect_to admin_user_path(user), success: "Permissions updated."
    end
  end

  private

  def permitted_names
    params.fetch(:permissions, []).intersection(Permission::AVAILABLE_PERMISSIONS)
  end

  def removing_admin?(user)
    user.admin? && !permitted_names.include?(Permission::ADMIN)
  end

  def only_admin?
    User.joins(:permissions)
      .where(permissions: { name: Permission::ADMIN })
      .lock
      .pluck(:id)
      .size == 1
  end

  def sync_permissions(user)
    current_names = user.permissions.pluck(:name)
    to_add = permitted_names - current_names
    to_remove = current_names - permitted_names
    user.permissions.where(name: to_remove).destroy_all
    to_add.each { |name| user.permissions.create!(name: name) }
  end
end
