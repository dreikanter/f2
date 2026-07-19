class FeedPolicy < ApplicationPolicy
  def index?
    authenticated? && user.active?
  end

  def show?
    owner?
  end

  def create?
    authenticated?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  # Refresh is meaningless for push-ingested (schedule-less) feeds — there is
  # no loader to run (spec 006 §7).
  def refresh?
    owner? && record.enabled? && record.scheduled?
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
