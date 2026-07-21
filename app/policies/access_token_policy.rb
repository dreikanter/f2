class AccessTokenPolicy < ApplicationPolicy
  def index?
    authenticated?
  end

  def show?
    owner?
  end

  def create?
    authenticated?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  private

  def owner?
    authenticated? && user == record.user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end
