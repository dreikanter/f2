class EventPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      admin_or_own_records
    end
  end
end
