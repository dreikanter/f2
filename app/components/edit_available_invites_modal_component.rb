class EditAvailableInvitesModalComponent < ViewComponent::Base
  def initialize(user:, modal_id: nil)
    @user = user
    @modal_id = modal_id || "edit-available-invites-modal-#{user.id}"
  end
end
