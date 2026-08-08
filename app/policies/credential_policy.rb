# Authorization shared by the provider credential types (AI and web search):
# any signed-in user may list their own and add more, and the owner or an admin
# may read, change, or remove an individual record.
#
# AccessTokenPolicy deliberately stays separate — tokens are owner-only, with no
# admin reach into someone else's.
class CredentialPolicy < ApplicationPolicy
  def index?
    authenticated?
  end

  def show?
    owner_or_admin?
  end

  def create?
    authenticated?
  end

  def update?
    owner_or_admin?
  end

  def destroy?
    owner_or_admin?
  end

  private

  def owner_or_admin?
    authenticated? && (user == record.user || admin?)
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
