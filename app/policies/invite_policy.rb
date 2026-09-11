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
      own_records(:created_by_user)
    end
  end
end
