class PostPolicy < ApplicationPolicy
  def index?
    authenticated? && user.active?
  end

  def show?
    owner?
  end

  def destroy?
    (owner? || admin?) && record.published?
  end

  private

  def owner?
    authenticated? && record.feed.user == user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user
        scope.joins(:feed).where(feeds: { user: user })
      else
        scope.none
      end
    end
  end
end
