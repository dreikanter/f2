class DevPolicy < ApplicationPolicy
  def show?
    user&.dev?
  end
end
