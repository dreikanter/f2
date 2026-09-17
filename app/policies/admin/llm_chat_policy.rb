class Admin::LlmChatPolicy < ApplicationPolicy
  def index?
    dev?
  end

  def show?
    dev?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.dev? ? scope.unexpired : scope.none
    end
  end
end
