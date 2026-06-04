class LlmCredentialPolicy < ApplicationPolicy
  def index?
    authenticated?
  end

  def show?
    owner_or_admin?
  end

  def create?
    authenticated?
  end

  def destroy?
    owner_or_admin?
  end

  def update?
    owner_or_admin?
  end

  private

  def owner_or_admin?
    authenticated? && (user == record.user || admin?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin?
        scope.all
      elsif user
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end
