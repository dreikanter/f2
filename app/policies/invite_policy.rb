class InvitePolicy < ApplicationPolicy
  def index?
    authenticated?
  end

  def create?
    return false unless authenticated?

    user.available_invites > user.created_invites.count
  end

  def destroy?
    return false unless authenticated?
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
