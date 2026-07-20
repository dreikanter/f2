module Admin
  # Authorizes the admin-only search credential inspection page. Kept separate
  # from the owner-scoped SearchCredentialPolicy so admin access never leaks
  # into the user-facing credential pages.
  class SearchCredentialPolicy < ApplicationPolicy
    def show?
      admin?
    end
  end
end
