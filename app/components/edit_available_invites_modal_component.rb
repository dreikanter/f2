class EditAvailableInvitesModalComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
    @modal_id = "edit-available-invites-modal-#{user.id}"
  end
end
