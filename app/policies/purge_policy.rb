class PurgePolicy < ApplicationPolicy
  def create?
    user&.admin?
  end
end
