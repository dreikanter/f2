class Development::RunPolicy < ApplicationPolicy
  def index?
    dev?
  end

  def create?
    dev?
  end
end
