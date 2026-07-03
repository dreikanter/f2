class Development::JobPolicy < ApplicationPolicy
  def index?
    dev?
  end
end
