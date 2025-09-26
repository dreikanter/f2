class AdminPolicy < ApplicationPolicy
  def show?
    admin?
  end
end
