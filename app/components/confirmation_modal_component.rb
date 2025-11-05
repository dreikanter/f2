class ConfirmationModalComponent < ViewComponent::Base
  def initialize(title:, details:, confirm_text:, confirm_url:, method: :post, modal_id: nil)
    @title = title
    @details = details
    @confirm_text = confirm_text
    @confirm_url = confirm_url
    @method = method
    @modal_id = modal_id || "modal-#{SecureRandom.hex(4)}"
  end
end
