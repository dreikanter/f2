module Admin
  # Authorizes the admin-only feed views, where operators inspect any user's
  # feed. Kept separate from the owner-scoped FeedPolicy so admin access never
  # leaks into the user-facing feed pages.
  class FeedPolicy < ApplicationPolicy
    def index?
      admin?
    end

    def show?
      admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        admin? ? scope.all : scope.none
      end
    end
  end
end
