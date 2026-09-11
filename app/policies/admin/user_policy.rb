class Admin::UserPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      admin_records
    end
  end
end
