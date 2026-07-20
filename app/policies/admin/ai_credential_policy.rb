module Admin
  # Authorizes the admin-only AI credential inspection page. Kept separate
  # from the owner-scoped AiCredentialPolicy so admin access never leaks into
  # the user-facing credential pages.
  class AiCredentialPolicy < ApplicationPolicy
    def show?
      admin?
    end
  end
end
