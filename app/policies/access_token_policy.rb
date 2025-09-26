class AccessTokenPolicy < ApplicationPolicy
  def index?
    user.present? && (user == record.user || admin?)
  end

  def show?
    user.present? && (user == record.user || admin?)
  end

  def create?
    user.present?
  end

  def update?
    user.present? && (user == record.user || admin?)
  end

  def destroy?
    user.present? && (user == record.user || admin?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      elsif user
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end