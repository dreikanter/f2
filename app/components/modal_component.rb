class ModalComponent < ViewComponent::Base
  renders_one :footer

  def initialize(title:, modal_id:)
    @title = title
    @modal_id = modal_id
  end
end
