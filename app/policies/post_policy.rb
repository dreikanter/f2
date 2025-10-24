class PostPolicy < ApplicationPolicy
  def index?
    user&.active?
  end

  def show?
    owner?
  end

  def destroy?
    (owner? || admin?) && record.published?
  end

  private

  def owner?
    user.present? && record.feed.user == user
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
