class Development::JobRunPolicy < ApplicationPolicy
  def index?
    dev?
  end

  def show?
    dev?
  end

  def create?
    dev?
  end
end
