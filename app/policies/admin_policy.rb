class AdminPolicy < ApplicationPolicy
  def show?
    admin?
  end

  def dev?
    user&.dev?
  end
end
