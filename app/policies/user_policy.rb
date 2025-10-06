class UserPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    self_or_admin?
  end

  def update?
    self_or_admin?
  end

  def destroy?
    admin?
  end

  private

  def self_or_admin?
    user.present? && (user == record || admin?)
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
