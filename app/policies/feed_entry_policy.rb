class FeedEntryPolicy < ApplicationPolicy
  def show?
    owner?
  end

  private

  def owner?
    authenticated? && record.feed.user_id == user.id
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
