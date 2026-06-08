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

  # The FreeFeed deletion option only makes sense when the post is actually
  # live on FreeFeed. A withdrawn post is already gone and a failed post never
  # got there, so in both cases the only thing left to remove is Feeder's
  # record of it.
  def freefeed_option?
    post.published? && post.freefeed_post_id.present?
  end

  def record_checked_by_default?
    !freefeed_option?
  end

  def intro_message
    if freefeed_option?
      "This post lives in two places: as a published post on FreeFeed, and as a record here in Feeder. Choose what you want to remove."
    elsif post.failed?
      "This post never made it to FreeFeed. You can still remove Feeder's record of it."
    else
      "This post is already gone from FreeFeed. You can still remove Feeder's record of it."
    end
  end

  def form_data
    data = { controller: "post-delete" }
    data[:turbo] = false unless turbo
    data
  end
end
