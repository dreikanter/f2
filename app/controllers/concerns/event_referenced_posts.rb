module EventReferencedPosts
  extend ActiveSupport::Concern

  private

  # Posts imported by the event, newest first, with feeds preloaded for cards.
  def referenced_posts(event)
    Post.where(id: event.event_references.where(reference_type: "Post").select(:reference_id))
        .includes(:feed)
        .order(created_at: :desc)
  end
end
