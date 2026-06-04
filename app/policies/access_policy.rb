class AccessPolicy < ApplicationPolicy
  def admin?
    user&.admin?
  end

  def dev?
    user&.dev?
  end
end
