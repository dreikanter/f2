class Admin::LlmChatPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      admin? ? scope.unexpired : scope.none
    end
  end
end
