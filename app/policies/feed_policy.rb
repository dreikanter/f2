class FeedPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present? && record.user == user
  end

  def create?
    user.present?
  end

  def update?
    user.present? && record.user == user
  end

  def destroy?
    user.present? && record.user == user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user
        scope.where(user: user)
      else
        scope.none
      end
    end
  end
end
