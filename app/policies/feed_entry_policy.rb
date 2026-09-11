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
      own_feed_records
    end
  end
end
