class UserPolicy < ApplicationPolicy
  def show?
    user.present? && (user == record || admin?)
  end

  def update?
    user.present? && (user == record || admin?)
  end

  def destroy?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(id: user.id)
      else
        scope.none
      end
    end
  end
end
