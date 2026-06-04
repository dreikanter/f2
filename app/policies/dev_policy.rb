class DevPolicy < ApplicationPolicy
  def show?
    dev?
  end
end
