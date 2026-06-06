class PostDeleteModalComponent < ViewComponent::Base
  def initialize(post:, turbo: true)
    @post = post
    @turbo = turbo
  end

  def self.modal_id(post)
    "delete-post-modal-#{post.id}"
  end

  private

  attr_reader :post, :turbo

  def modal_id
    self.class.modal_id(post)
  end

  def form_data
    data = { controller: "post-delete" }
    data[:turbo] = false unless turbo
    data
  end
end
