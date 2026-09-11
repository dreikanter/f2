class PostPolicy < ApplicationPolicy
  def index?
    authenticated? && user.active?
  end

  def show?
    owner?
  end

  def destroy?
    (owner? || admin?) && (record.published? || record.withdrawn? || record.failed?)
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
