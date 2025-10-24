class FeedPolicy < ApplicationPolicy
  def index?
    authenticated? && user.active?
  end

  def show?
    owner?
  end

  def create?
    user.present?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  def purge?
    owner?
  end

  private

  def owner?
    authenticated? && record.user == user
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
