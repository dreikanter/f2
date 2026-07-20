module Admin
  # Authorizes the admin-only access token inspection page. Kept separate from
  # the owner-scoped AccessTokenPolicy so admin access never leaks into the
  # user-facing token pages.
  class AccessTokenPolicy < ApplicationPolicy
    def show?
      admin?
    end
  end
end
