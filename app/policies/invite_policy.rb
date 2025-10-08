class InvitePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present? && user.available_invites > user.created_invites.where(invited_user_id: nil).count
  end

  def destroy?
    return false unless user.present?
    return false if record.used?

    user == record.created_by_user || admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(created_by_user: user)
      else
        scope.none
      end
    end
  end
end
