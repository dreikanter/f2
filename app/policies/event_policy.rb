# frozen_string_literal: true

class EventPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      else
        scope.none
      end
    end

    private

    def admin?
      user&.permissions&.exists?(name: "admin")
    end
  end
end
