# Shared access rules for AI and search credentials: owners manage their own,
# and admins can manage credentials across users.
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
      admin_or_own_records
    end
  end
end
