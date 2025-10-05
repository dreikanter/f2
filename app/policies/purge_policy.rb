class PurgePolicy < ApplicationPolicy
  def create?
    admin?
  end
end
