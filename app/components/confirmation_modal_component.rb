class ConfirmationModalComponent < ViewComponent::Base
  def initialize(title:, action:, url:, method: :post, modal_id: nil)
    @title = title
    @action = action
    @url = url
    @method = method
    @modal_id = modal_id || "modal-#{SecureRandom.hex(4)}"
  end
end
